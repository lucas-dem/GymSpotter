"use client";

import { useEffect, useRef, useState } from "react";
import { Dumbbell, Pause, Play } from "lucide-react";
import { exercisePlayback, exerciseVisuals } from "@/lib/exercise-visuals";

type Props = {
  exercise: { slug: string; name: string; mediaPath: string | null };
  thumbnail?: boolean;
};

export function ExerciseDemonstration({ exercise, thumbnail = false }: Props) {
  return <Demonstration key={`${exercise.slug}-${thumbnail}`} exercise={exercise} thumbnail={thumbnail} />;
}

function Demonstration({ exercise, thumbnail }: Props) {
  const visual = exerciseVisuals[exercise.slug];
  const root = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [visible, setVisible] = useState(false);
  const [pageVisible, setPageVisible] = useState(true);
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);
  const [fallbackFailed, setFallbackFailed] = useState(false);
  const frame = exercisePlayback[position];
  const spriteFrame = visual?.frameOrder?.[frame] ?? frame;

  useEffect(() => {
    if (thumbnail || !visual) return;
    const preference = window.matchMedia("(prefers-reduced-motion: reduce)");
    const syncMotion = () => setPlaying(!preference.matches);
    const syncVisibility = () => setPageVisible(document.visibilityState === "visible");
    syncMotion();
    syncVisibility();
    preference.addEventListener("change", syncMotion);
    document.addEventListener("visibilitychange", syncVisibility);
    const observer = new IntersectionObserver(([entry]) => setVisible(entry.isIntersecting));
    if (root.current) observer.observe(root.current);
    return () => {
      preference.removeEventListener("change", syncMotion);
      document.removeEventListener("visibilitychange", syncVisibility);
      observer.disconnect();
    };
  }, [thumbnail, visual]);

  useEffect(() => {
    if (!playing || !visible || !pageVisible || !ready || failed || thumbnail) return;
    const timer = window.setTimeout(() => setPosition((current) => (current + 1) % exercisePlayback.length), position % 2 === 0 ? 1200 : 800);
    return () => window.clearTimeout(timer);
  }, [playing, visible, pageVisible, ready, failed, thumbnail, position]);

  if (!visual || failed) return <div className="grid h-full min-h-44 place-items-center bg-white text-neutral-500">
    {exercise.mediaPath && !fallbackFailed ? <img src={exercise.mediaPath} alt={`Demostración de ${exercise.name}`} className="h-full max-h-80 w-full object-contain" onError={() => setFallbackFailed(true)} /> : <div className="flex flex-col items-center gap-2 p-6"><Dumbbell className="size-12" /><span className="text-sm">Demostración no disponible</span></div>}
  </div>;

  const title = position === 3 ? "Regreso" : ["Inicio", "Recorrido", "Final"][frame];
  return <div ref={root} className={thumbnail ? "h-full bg-white" : "bg-[#171a17]"}>
    <div className={`flex justify-center overflow-hidden bg-white ${thumbnail ? "h-full" : "h-[min(76vw,340px)]"}`}>
      <div className="relative aspect-square h-full overflow-hidden" role="img" aria-label={`${exercise.name}: ${title.toLowerCase()}. ${visual.cues[frame]}`}>
        <img
          src={visual.src}
          alt=""
          aria-hidden="true"
          width={2172}
          height={724}
          loading={thumbnail ? "lazy" : "eager"}
          decoding="async"
          onLoad={() => setReady(true)}
          onError={() => setFailed(true)}
          style={{ width: "300%", maxWidth: "none", height: "100%", transform: `translateX(-${spriteFrame * 100 / 3}%)` }}
        />
      </div>
    </div>
    {!thumbnail && <div className="space-y-3 border-t border-white/10 px-4 py-4 text-white">
      <div className="flex flex-wrap items-center gap-2">
        <button type="button" disabled={!ready} onClick={() => setPlaying((value) => !value)} aria-label={playing ? "Pausar demostración" : "Reproducir demostración"} className="flex min-h-11 items-center gap-2 rounded-lg bg-[#e21b2d] px-3 text-sm font-bold text-white disabled:opacity-40">
          {playing ? <Pause className="size-4" /> : <Play className="size-4" />}{playing ? "Pausar" : "Reproducir"}
        </button>
        <div className="flex gap-1" role="group" aria-label="Posiciones del ejercicio">
          {["Inicio", "Mitad", "Final"].map((label, index) => <button type="button" key={label} aria-pressed={frame === index} onClick={() => { setPosition(index); setPlaying(false); }} className={`min-h-11 rounded-lg px-3 text-sm font-bold ${frame === index ? "bg-white/20 text-white" : "bg-white/5 text-white/60 hover:bg-white/10"}`}>{index + 1}<span className="sr-only">: {label}</span></button>)}
        </div>
        <span className="text-sm text-white/60">{title} · {frame + 1}/3</span>
      </div>
      <p className="min-h-10 text-sm leading-5 text-white/80">{position === 3 ? "Volvé por el mismo recorrido, sin soltar el peso de golpe." : visual.cues[frame]}</p>
    </div>}
  </div>;
}
