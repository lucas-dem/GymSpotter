"use client";

import bodyPaths from "@/app/data/body-paths";

type MuscleLoad = { muscle: string; completedAt: string; sets: number };
type ViewGeometry = { vb: string; p: Record<string, string[]> };

const activeMuscles = [
  "trapezius", "deltoids", "chest", "upper-back", "serratus", "biceps", "triceps",
  "forearm", "abs", "obliques", "lower-back", "gluteal", "quadriceps", "hamstring",
  "adductors", "hip-flexors", "calves", "tibialis",
];
const inertParts = ["head", "hair", "neck", "hands", "feet", "knees", "ankles"];

const muscleAliases: Record<string, string[]> = {
  Pecho: ["chest", "serratus", "deltoids", "triceps"],
  "Pecho superior": ["chest", "deltoids", "triceps"],
  Pectoral: ["chest", "deltoids"],
  "Tríceps": ["triceps"],
  Cuádriceps: ["quadriceps", "gluteal"],
  Espalda: ["upper-back", "biceps", "forearm"],
};

function fatigueLevels(loads: MuscleLoad[]) {
  const levels: Record<string, number> = {};
  const now = Date.now();
  for (const load of loads) {
    const hours = Math.max(0, (now - new Date(load.completedAt).getTime()) / 3_600_000);
    const freshness = hours <= 24 ? 4 : hours <= 48 ? 3 : hours <= 72 ? 2 : hours <= 120 ? 1 : 0;
    const volume = load.sets >= 4 ? 1 : 0;
    for (const slug of muscleAliases[load.muscle] ?? []) levels[slug] = Math.max(levels[slug] ?? 0, Math.min(4, freshness + volume));
  }
  return levels;
}

function BodyView({ geometry, levels }: { geometry: ViewGeometry; levels: Record<string, number> }) {
  return <svg viewBox={geometry.vb} className="body-fatigue-view" role="img" aria-label="Mapa anatómico de fatiga muscular">
    {inertParts.flatMap((slug) => (geometry.p[slug] ?? []).map((path, index) => <path key={`${slug}-${index}`} className="body-fatigue-silhouette" d={path} />))}
    {activeMuscles.flatMap((slug) => (geometry.p[slug] ?? []).map((path, index) => <path key={`${slug}-${index}`} className={`body-fatigue-muscle fatigue-${levels[slug] ?? 0}`} d={path}><title>{slug}</title></path>))}
  </svg>;
}

export function BodyFatigueMap({ loads }: { loads: MuscleLoad[] }) {
  const levels = fatigueLevels(loads);
  const geometry = bodyPaths.male as { front: ViewGeometry; back: ViewGeometry };
  const hasHistory = loads.length > 0;
  return <div>
    <div className="body-fatigue-map">
      <BodyView geometry={geometry.front} levels={levels} />
      <BodyView geometry={geometry.back} levels={levels} />
    </div>
    <div className="mt-4 flex flex-wrap justify-center gap-4 text-xs font-semibold text-white/45">
      <span className="flex items-center gap-1.5"><i className="size-2.5 rounded-sm bg-red-500" /> Fatigado</span>
      <span className="flex items-center gap-1.5"><i className="size-2.5 rounded-sm bg-amber-400" /> Recuperando</span>
      <span className="flex items-center gap-1.5"><i className="size-2.5 rounded-sm bg-[#d8dbe0]" /> Listo</span>
    </div>
    <p className="mt-4 text-center text-sm text-white/35">{hasHistory ? "Calculado con tus series de los últimos 7 días." : "Todavía no hay series recientes: todo figura listo para entrenar."}</p>
  </div>;
}
