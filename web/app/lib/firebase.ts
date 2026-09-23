import {initializeApp, getApps} from 'firebase/app';
import {
  GoogleAuthProvider,
  createUserWithEmailAndPassword,
  getAuth,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut,
  type User,
} from 'firebase/auth';
import {
  arrayUnion,
  collection,
  doc,
  getDoc,
  getDocs,
  getFirestore,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  where,
  writeBatch,
  type DocumentReference,
} from 'firebase/firestore';
import {type Database, type Review, type Word} from './vocabulary';

const config = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID,
};

export const firebaseConfigured = Boolean(
  config.apiKey &&
  config.authDomain &&
  config.projectId &&
  config.appId,
);

const app = firebaseConfigured ? getApps()[0] ?? initializeApp(config) : null;
export const auth = app ? getAuth(app) : null;
export const firestore = app ? getFirestore(app) : null;

export type CloudScope =
  | {type:'personal'}
  | {type:'group';groupId:string};

const REVIEW_STORAGE_VERSION=3;
const CLOUD_SYNC_OVERLAP_MS=5000;
const groupMembershipCache=new Set<string>();

export type CloudLoadResult={
  database:Database;
  cursorMs:number;
};

type StoredReview = Review & {id?:string};
type CloudWordData = Word & {
  _reviewEvents?:string[];
  updatedAt?:unknown;
  updatedBy?:string;
};

export function listenFirebaseUser(callback:(user:User|null)=>void) {
  if(!auth)return ()=>{};
  return onAuthStateChanged(auth,callback);
}

export async function signInEmail(
  email:string,
  password:string,
  createAccount=false,
) {
  if(!auth)throw new Error('Firebase 설정이 필요합니다.');
  return createAccount
    ?createUserWithEmailAndPassword(auth,email,password)
    :signInWithEmailAndPassword(auth,email,password);
}

export async function signInGoogle() {
  if(!auth)throw new Error('Firebase 설정이 필요합니다.');
  return signInWithPopup(auth,new GoogleAuthProvider());
}

export async function signOutFirebase() {
  if(!auth)throw new Error('Firebase 설정이 필요합니다.');
  return signOut(auth);
}

function rootPath(uid:string,scope:CloudScope) {
  return scope.type==='personal'
    ?['users',uid] as const
    :['groups',scope.groupId] as const;
}

function normalizeCategories(database:Database) {
  return [...new Set([
    ...(database.categories??[]),
    ...database.words
      .map(word=>(word.category??'').trim())
      .filter(Boolean),
  ])].sort((a,b)=>a.localeCompare(b,'ko'));
}

function cleanWordForCloud(word:Word):Word {
  return JSON.parse(JSON.stringify(word)) as Word;
}

function reviewId(
  review:StoredReview,
  wordIndex:number,
) {
  return review.id?.trim() ||
    `legacy:${review.date}:${review.correct?'1':'0'}:${wordIndex}`;
}

function encodeReviewEvent(
  review:StoredReview,
  wordIndex:number,
) {
  return JSON.stringify([
    reviewId(review,wordIndex),
    review.date,
    review.correct?1:0,
  ]);
}

function decodeReviewEvent(
  raw:string,
  wordId:string,
):StoredReview|null {
  try {
    const parsed=JSON.parse(raw);
    if(
      !Array.isArray(parsed) ||
      parsed.length<3 ||
      typeof parsed[0]!=='string' ||
      typeof parsed[1]!=='string' ||
      (parsed[2]!==0&&parsed[2]!==1)
    )return null;

    return {
      id:parsed[0],
      date:parsed[1],
      correct:parsed[2]===1,
      wordId,
    };
  } catch {
    return null;
  }
}

function reviewEventsFor(
  reviews:Database['reviews'],
  wordId:string,
) {
  return reviews
    .filter(review=>review.wordId===wordId)
    .map((review,index)=>encodeReviewEvent(review as StoredReview,index));
}

function reviewsFromCloudWord(
  data:Record<string,unknown>,
  wordId:string,
) {
  const events=Array.isArray(data._reviewEvents)
    ?data._reviewEvents.filter((item):item is string=>typeof item==='string')
    :[];

  return events.flatMap(event=>{
    const review=decodeReviewEvent(event,wordId);
    return review?[review]:[];
  });
}

function wordFromCloudData(data:Record<string,unknown>):Word {
  const {
    _reviewEvents:_ignoredReviews,
    updatedAt:_ignoredUpdatedAt,
    updatedBy:_ignoredUpdatedBy,
    deleted:_ignoredDeleted,
    ...word
  }=data;

  return word as Word;
}

async function commitWriteChunks(
  writes:((batch:ReturnType<typeof writeBatch>)=>void)[],
) {
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');
  if(!writes.length)return;

  for(let start=0;start<writes.length;start+=450) {
    const batch=writeBatch(firestore);
    for(const write of writes.slice(start,start+450))write(batch);
    await batch.commit();
  }
}

async function ensureGroupMember(
  uid:string,
  groupId:string,
  email:string|null,
) {
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');

  const cacheKey=`${uid}:${groupId}`;
  if(groupMembershipCache.has(cacheKey))return;

  const groupRef=doc(firestore,'groups',groupId);

  try {
    const existing=await getDoc(groupRef);

    if(existing.exists()) {
      if(existing.data().memberUids?.[uid]!==true) {
        throw new Error('그룹 소유자에게 멤버 초대를 요청해주세요.');
      }

      groupMembershipCache.add(cacheKey);
      return;
    }
  } catch(error) {
    // Firestore rules may hide an existing group from non-members.
    if((error as {code?:string}).code!=='permission-denied')throw error;
  }

  await setDoc(groupRef,{
    name:groupId,
    ownerUid:uid,
    memberUids:{[uid]:true},
    memberEmails:{[uid]:email??''},
    updatedAt:serverTimestamp(),
    createdAt:serverTimestamp(),
  },{merge:true});

  await setDoc(doc(firestore,'users',uid,'groups',groupId),{
    name:groupId,
    role:'member',
    updatedAt:serverTimestamp(),
  },{merge:true});

  groupMembershipCache.add(cacheKey);
}

async function migrateLegacyReviews(
  rootRef:DocumentReference,
  user:User,
  words:Word[],
  legacyReviews:StoredReview[],
) {
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');

  const writes:((batch:ReturnType<typeof writeBatch>)=>void)[]=[];

  for(const word of words) {
    const events=reviewEventsFor(legacyReviews,word.id);
    if(!events.length)continue;

    writes.push(batch=>batch.set(
      doc(rootRef,'words',word.id),
      {
        _reviewEvents:events,
        updatedAt:serverTimestamp(),
        updatedBy:user.uid,
      },
      {merge:true},
    ));
  }

  writes.push(batch=>batch.set(
    rootRef,
    {
      reviewStorageVersion:REVIEW_STORAGE_VERSION,
      updatedAt:serverTimestamp(),
      updatedBy:user.uid,
    },
    {merge:true},
  ));

  await commitWriteChunks(writes);
}

function sameWord(a:Word|undefined,b:Word|undefined) {
  if(!a||!b)return a===b;
  return JSON.stringify(a)===JSON.stringify(b);
}

function sameStringArray(a:string[],b:string[]) {
  if(a.length!==b.length)return false;
  for(let index=0;index<a.length;index++) {
    if(a[index]!==b[index])return false;
  }
  return true;
}

/**
 * Incremental cloud sync.
 *
 * No collection scan is performed here. Only changed word documents,
 * deleted word documents, and changed metadata are written.
 *
 * Study reviews are stored inside each word document as an unindexed
 * array of compact event strings. Appending a quiz result uses arrayUnion,
 * so one answered question normally costs exactly one Firestore document write.
 */
export async function syncCloudDatabase(
  user:User,
  scope:CloudScope,
  previous:Database,
  next:Database,
) {
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');

  if(scope.type==='group') {
    await ensureGroupMember(user.uid,scope.groupId,user.email);
  }

  const [rootCollection,rootId]=rootPath(user.uid,scope);
  const rootRef=doc(firestore,rootCollection,rootId);

  const previousWords=new Map(
    previous.words.map(word=>[word.id,word]),
  );
  const nextWords=new Map(
    next.words.map(word=>[word.id,word]),
  );

  const writes:((batch:ReturnType<typeof writeBatch>)=>void)[]=[];

  for(const previousWord of previous.words) {
    if(!nextWords.has(previousWord.id)) {
      writes.push(batch=>batch.set(
        doc(rootRef,'words',previousWord.id),
        {
          deleted:true,
          updatedAt:serverTimestamp(),
          updatedBy:user.uid,
        },
        {merge:true},
      ));
    }
  }

  for(const nextWord of next.words) {
    const previousWord=previousWords.get(nextWord.id);
    const previousEvents=reviewEventsFor(previous.reviews,nextWord.id);
    const nextEvents=reviewEventsFor(next.reviews,nextWord.id);

    const previousEventSet=new Set(previousEvents);
    const nextEventSet=new Set(nextEvents);
    const addedEvents=nextEvents.filter(event=>!previousEventSet.has(event));
    const removedEvent=
      previousEvents.some(event=>!nextEventSet.has(event));

    const wordChanged=!sameWord(previousWord,nextWord);
    const reviewChanged=addedEvents.length>0||removedEvent;

    if(!wordChanged&&!reviewChanged)continue;

    const payload:Record<string,unknown>={
      ...cleanWordForCloud(nextWord),
      updatedAt:serverTimestamp(),
      updatedBy:user.uid,
      deleted:false,
    };

    if(!previousWord||removedEvent) {
      // New word or an explicit history rewrite.
      payload._reviewEvents=nextEvents;
    } else if(addedEvents.length) {
      // Normal quiz path: append only, preserving concurrent events
      // created on another device without performing a read.
      payload._reviewEvents=arrayUnion(...addedEvents);
    }

    writes.push(batch=>batch.set(
      doc(rootRef,'words',nextWord.id),
      payload,
      {merge:true},
    ));
  }

  const previousCategories=normalizeCategories(previous);
  const nextCategories=normalizeCategories(next);

  if(
    previous.version!==next.version ||
    !sameStringArray(previousCategories,nextCategories)
  ) {
    writes.push(batch=>batch.set(
      rootRef,
      {
        version:next.version,
        categories:nextCategories,
        reviewStorageVersion:REVIEW_STORAGE_VERSION,
        updatedAt:serverTimestamp(),
        updatedBy:user.uid,
      },
      {merge:true},
    ));
  }

  await commitWriteChunks(writes);
}

/**
 * Full cloud load + server updatedAt cursor.
 */
export async function loadCloudDatabaseWithCursor(
  user:User,
  scope:CloudScope,
):Promise<CloudLoadResult> {
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');

  if(scope.type==='group') {
    await ensureGroupMember(user.uid,scope.groupId,user.email);
  }

  const [rootCollection,rootId]=rootPath(user.uid,scope);
  const rootRef=doc(firestore,rootCollection,rootId);

  const [rootSnap,wordSnap]=await Promise.all([
    getDoc(rootRef),
    getDocs(query(collection(rootRef,'words'),orderBy('created','desc'))),
  ]);

  const rootData=rootSnap.data() as
    | (Partial<Database> & {reviewStorageVersion?:number})
    | undefined;

  const all=wordSnap.docs.map(item=>({
    id:item.id,
    data:item.data() as Record<string,unknown>,
  }));

  const active=all.filter(item=>item.data.deleted!==true);
  const words=active.map(item=>wordFromCloudData({...item.data,id:item.id}));

  const storedCategories=Array.isArray(rootData?.categories)
    ?rootData.categories.filter((item):item is string=>typeof item==='string')
    :[];

  const categories=[...new Set([
    ...storedCategories,
    ...words.map(word=>(word.category??'').trim()).filter(Boolean),
  ])];

  const cursorMs=all.reduce((max,item)=>{
    const value=item.data.updatedAt;
    return value instanceof Timestamp?Math.max(max,value.toMillis()):max;
  },0);

  if(rootData?.reviewStorageVersion===REVIEW_STORAGE_VERSION) {
    return {
      database:{
        version:1,
        categories,
        words,
        reviews:active.flatMap(item=>reviewsFromCloudWord(item.data,item.id)),
      },
      cursorMs,
    };
  }

  const legacySnap=await getDocs(collection(rootRef,'reviews'));
  const legacyReviews=legacySnap.docs.map((item,readIndex)=>{
    const review=item.data() as Review;
    const suffix=Number(item.id.split('-').at(-1));
    return {
      review:{...review,id:`legacy:${item.id}`} as StoredReview,
      readIndex,
      legacyIndex:Number.isFinite(suffix)?suffix:readIndex,
    };
  }).sort((a,b)=>
    a.review.date.localeCompare(b.review.date) ||
    a.legacyIndex-b.legacyIndex ||
    a.readIndex-b.readIndex
  ).map(item=>item.review);

  await migrateLegacyReviews(rootRef,user,words,legacyReviews);

  return {
    database:{version:1,categories,words,reviews:legacyReviews},
    cursorMs,
  };
}

export async function loadCloudDatabaseChanges(
  user:User,
  scope:CloudScope,
  base:Database,
  sinceMs:number,
):Promise<CloudLoadResult> {
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');

  if(scope.type==='group') {
    await ensureGroupMember(user.uid,scope.groupId,user.email);
  }

  const [rootCollection,rootId]=rootPath(user.uid,scope);
  const rootRef=doc(firestore,rootCollection,rootId);
  const threshold=Timestamp.fromMillis(
    Math.max(0,sinceMs-CLOUD_SYNC_OVERLAP_MS),
  );

  const [rootSnap,changedSnap]=await Promise.all([
    getDoc(rootRef),
    getDocs(query(
      collection(rootRef,'words'),
      where('updatedAt','>',threshold),
      orderBy('updatedAt','asc'),
    )),
  ]);

  const wordsById=new Map(base.words.map(word=>[word.id,word]));
  const reviewsByWord=new Map<string,Database['reviews']>();

  for(const review of base.reviews){
    const list=reviewsByWord.get(review.wordId)??[];
    list.push(review);
    reviewsByWord.set(review.wordId,list);
  }

  let cursorMs=sinceMs;

  for(const item of changedSnap.docs){
    const data=item.data() as Record<string,unknown>;
    const updatedAt=data.updatedAt;
    if(updatedAt instanceof Timestamp){
      cursorMs=Math.max(cursorMs,updatedAt.toMillis());
    }

    if(data.deleted===true){
      wordsById.delete(item.id);
      reviewsByWord.delete(item.id);
      continue;
    }

    wordsById.set(item.id,wordFromCloudData({...data,id:item.id}));
    reviewsByWord.set(item.id,reviewsFromCloudWord(data,item.id));
  }

  const words=[...wordsById.values()]
    .sort((a,b)=>(b.created??0)-(a.created??0));

  const rootData=rootSnap.data() as Partial<Database>|undefined;
  const storedCategories=Array.isArray(rootData?.categories)
    ?rootData.categories.filter((item):item is string=>typeof item==='string')
    :[];

  const categories=[...new Set([
    ...storedCategories,
    ...words.map(word=>(word.category??'').trim()).filter(Boolean),
  ])];

  return {
    database:{
      version:1,
      categories,
      words,
      reviews:[...reviewsByWord.values()].flat(),
    },
    cursorMs,
  };
}

export async function loadCloudDatabase(
  user:User,
  scope:CloudScope,
):Promise<Database> {
  return (await loadCloudDatabaseWithCursor(user,scope)).database;
}

/**
 * Backwards-compatible explicit full-save API.
 * New application code should use syncCloudDatabase with an in-memory base.
 */
export async function saveCloudDatabase(
  user:User,
  scope:CloudScope,
  database:Database,
) {
  const previous=await loadCloudDatabase(user,scope);
  await syncCloudDatabase(user,scope,previous,database);
}
