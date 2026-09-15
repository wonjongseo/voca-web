import type { Metadata } from "next";
import { headers } from 'next/headers';
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get('host') || 'localhost:3000';
  const protocol = host.startsWith('localhost') || host.startsWith('127.0.0.1') ? 'http' : 'https';
  const image = `${protocol}://${host}/og.png`;
  return {
  title: "LEAF | 나의 단어장",
  description: "단어를 모으고 매일 복습하며 나만의 어휘를 넓혀보세요.",
  openGraph: {title:'LEAF | 나의 단어장',description:'단어를 모으고 매일 복습하며 나만의 어휘를 넓혀보세요.',images:[image]},
  twitter: {card:'summary_large_image',title:'LEAF | 나의 단어장',description:'단어를 모으고 매일 복습하며 나만의 어휘를 넓혀보세요.',images:[image]},
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko">
      <body>
        {children}
      </body>
    </html>
  );
}
