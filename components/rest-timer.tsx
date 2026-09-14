"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { BellRing, Pause, Play, RotateCcw, Timer, X } from "lucide-react";
import { Button } from "@/components/ui/button";

const presets = [60, 180, 300, 600];
const labelFor = (seconds: number) => `${seconds / 60} min`;

export function RestTimer({ embedded = false }: { embedded?: boolean }) {
  const [open, setOpen] = useState(false);
  const [selected, setSelected] = useState(90);
  const [remaining, setRemaining] = useState(90);
  const [running, setRunning] = useState(false);
  const notified = useRef(false);
  const finished = remaining === 0;

  useEffect(() => {
    if (!running || remaining <= 0) return;
    const id = window.setInterval(() => setRemaining((value) => { if (value <= 1) { setRunning(false); return 0; } return value - 1; }), 1000);
    return () => window.clearInterval(id);
  }, [running, remaining]);

  useEffect(() => {
    if (!finished || notified.current) return;
    notified.current = true;
    if ("vibrate" in navigator) navigator.vibrate([250, 120, 250]);
  }, [finished]);

  const display = useMemo(() => `${Math.floor(remaining / 60).toString().padStart(2, "0")}:${(remaining % 60).toString().padStart(2, "0")}`, [remaining]);
  const choose = (seconds: number) => { notified.current = false; setSelected(seconds); setRemaining(seconds); setRunning(false); };
  const reset = () => { notified.current = false; setRemaining(selected); setRunning(false); };

  return <div className={embedded ? "mt-5" : "fixed bottom-20 right-4 z-40 sm:bottom-6 sm:right-6"}>
    {open && <div className="mb-3 w-[min(20rem,calc(100vw-2rem))] rounded-3xl border border-white/12 bg-[#15171b]/95 p-4 text-white shadow-2xl backdrop-blur-xl">
      <div className="flex items-center justify-between"><div><p className="text-xs font-black uppercase tracking-[.14em] text-[#e21b2d]">Descanso</p><p className="mt-1 text-4xl font-black tabular-nums">{display}</p></div><Button onClick={() => setOpen(false)} variant="ghost" size="icon" className="rounded-full text-white/50"><X /></Button></div>
      <div className="mt-4 grid grid-cols-4 gap-2">{presets.map((seconds) => <button key={seconds} onClick={() => choose(seconds)} className={`rounded-xl border py-2 text-sm font-bold ${selected === seconds ? "border-[#e21b2d] bg-[#e21b2d] text-white" : "border-white/10 bg-white/5 text-white/65"}`}>{labelFor(seconds)}</button>)}</div>
      <div className="mt-4 flex gap-2"><Button onClick={() => setRunning((value) => !value)} className="h-11 flex-1 bg-[#e21b2d] font-black text-white">{running ? <Pause /> : <Play />} {running ? "Pausar" : finished ? "Reiniciar" : "Iniciar"}</Button><Button onClick={reset} variant="outline" size="icon" className="h-11 border-white/15 bg-white/5"><RotateCcw /></Button></div>
      {finished && <p className="mt-3 flex items-center justify-center gap-2 text-sm font-bold text-[#d8dbe0]"><BellRing className="size-4" /> Descanso terminado</p>}
    </div>}
    <Button onClick={() => setOpen((value) => !value)} aria-label="Abrir timer de descanso" className={embedded ? "h-11 rounded-xl bg-[#e21b2d] px-4 font-black text-white hover:bg-[#bd1626]" : "size-14 rounded-full bg-[#e21b2d] p-0 text-white shadow-[0_10px_35px_rgba(226,27,45,.35)] hover:bg-[#bd1626]"}><Timer className="size-5" />{embedded && " Timer de descanso"}</Button>
  </div>;
}
