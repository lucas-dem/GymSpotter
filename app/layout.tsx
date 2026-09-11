import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "GymSpotter — Tu entrenamiento, acompañado",
  description: "Membresía, rutinas y seguimiento con tu entrenador en un solo lugar.",
  icons: { icon: "/favicon.svg", shortcut: "/favicon.svg" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="es"><body className="antialiased">{children}</body></html>; }
