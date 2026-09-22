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
  collection,
  doc,
  getDoc,
  getDocs,
  getFirestore,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  writeBatch,
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

export type CloudScope = {type:'personal'}|{type:'group';groupId:string};

export function listenFirebaseUser(callback:(user:User|null)=>void) {
  if(!auth)return ()=>{};
  return onAuthStateChanged(auth,callback);
}

export async function signInEmail(email:string,password:string,createAccount=false) {
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

function reviewDocId(review:Review,index:number) {
  return `${review.date}-${review.wordId}-${index}`;
}

async function commitWriteChunks(writes:((batch:ReturnType<typeof writeBatch>)=>void)[]) {
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');
  for(let start=0;start<writes.length;start+=450) {
    const batch=writeBatch(firestore);
    for(const write of writes.slice(start,start+450))write(batch);
    await batch.commit();
  }
}

async function ensureGroupMember(uid:string,groupId:string,email:string|null) {
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');
  const groupRef=doc(firestore,'groups',groupId);
  try {
    const existing=await getDoc(groupRef);
    if(existing.exists()) {
      if(existing.data().memberUids?.[uid]!==true)throw new Error('그룹 소유자에게 멤버 초대를 요청해주세요.');
      return;
    }
  } catch(error) {
    // Rules hide absent/non-member groups. A create below is allowed only for
    // a new group; existing non-members remain denied by Firestore rules.
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
}

export async function saveCloudDatabase(user:User,scope:CloudScope,database:Database) {
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');
  if(scope.type==='group')await ensureGroupMember(user.uid,scope.groupId,user.email);

  const [rootCollection,rootId]=rootPath(user.uid,scope);
  const rootRef=doc(firestore,rootCollection,rootId);
  const [existingWords,existingReviews]=await Promise.all([
    getDocs(collection(rootRef,'words')),
    getDocs(collection(rootRef,'reviews')),
  ]);
  const nextWordIds=new Set(database.words.map(word=>word.id));
  const nextReviewIds=new Set(database.reviews.map(reviewDocId));
  const writes:((batch:ReturnType<typeof writeBatch>)=>void)[]=[
    batch=>batch.set(rootRef,{
      version:database.version,
      categories:database.categories??[],
      updatedAt:serverTimestamp(),
      updatedBy:user.uid,
    },{merge:true}),
  ];

  for(const item of existingWords.docs) {
    if(!nextWordIds.has(item.id))writes.push(batch=>batch.delete(item.ref));
  }
  for(const item of existingReviews.docs) {
    if(!nextReviewIds.has(item.id))writes.push(batch=>batch.delete(item.ref));
  }
  for(const word of database.words){
    writes.push(batch=>batch.set(doc(rootRef,'words',word.id),{...word,updatedAt:serverTimestamp(),updatedBy:user.uid}));
  }
  for(const [index,review] of database.reviews.entries()){
    writes.push(batch=>batch.set(doc(rootRef,'reviews',reviewDocId(review,index)),review));
  }

  await commitWriteChunks(writes);
}

export async function loadCloudDatabase(user:User,scope:CloudScope):Promise<Database> {
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');
  if(scope.type==='group')await ensureGroupMember(user.uid,scope.groupId,user.email);

  const [rootCollection,rootId]=rootPath(user.uid,scope);
  const rootRef=doc(firestore,rootCollection,rootId);
  const [rootSnap,wordSnap,reviewSnap]=await Promise.all([
    getDoc(rootRef),
    getDocs(query(collection(rootRef,'words'),orderBy('created','desc'))),
    getDocs(collection(rootRef,'reviews')),
  ]);

  const rootData=rootSnap.data() as Partial<Database>|undefined;
  return {
    version:1,
    categories:Array.isArray(rootData?.categories)?rootData.categories.filter((item):item is string=>typeof item==='string'):[],
    words:wordSnap.docs.map(item=>item.data() as Word),
    reviews:reviewSnap.docs.map(item=>item.data() as Review),
  };
}
