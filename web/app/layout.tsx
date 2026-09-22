import type { Metadata } from "next";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  return {
  title: "Leafy | 나의 단어장",
  description: "단어를 모으고 매일 복습하며 나만의 어휘를 넓혀보세요.",
  icons: {icon:"/favicon.svg",shortcut:"/favicon.svg"},
  openGraph: {title:'Leafy | 나의 단어장',description:'단어를 모으고 매일 복습하며 나만의 어휘를 넓혀보세요.',images:[]},
  twitter: {card:'summary',title:'Leafy | 나의 단어장',description:'단어를 모으고 매일 복습하며 나만의 어휘를 넓혀보세요.',images:[]},
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko" suppressHydrationWarning>
      <body suppressHydrationWarning>
        {children}
      </body>
    </html>
  );
}
