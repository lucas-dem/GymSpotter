"use client";

import { Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

type CatalogExercise = {
  id: number;
  slug: string;
  name: string;
  muscle: string;
  equipment: string;
  instructions: string;
  mediaPath: string | null;
};

export type RoutineDraftRow = {
  key: string;
  exerciseId: number;
  dayName: string;
  dayTitle: string;
  sets: number;
  repsMin: number;
  repsMax: number;
  targetWeight: number;
  targetRir: number;
  restSeconds: number;
};

type RoutineViewRow = CatalogExercise & Omit<RoutineDraftRow, "key"> & { id: number };

const numberValue = (value: string, fallback: number) => Number.isFinite(Number(value)) ? Number(value) : fallback;
const inputClass = "h-9 min-w-0 border-white/10 bg-white/5 px-2 text-center text-sm";

export function RoutineTableView({ rows, onExercise }: { rows: RoutineViewRow[]; onExercise: (exercise: CatalogExercise) => void }) {
  const days = [...new Set(rows.map((row) => row.dayName))];
  if (!rows.length) return <div className="rounded-2xl border border-dashed border-white/15 p-8 text-center text-white/45">Todavía no hay ejercicios en esta rutina.</div>;
  return <div className="space-y-5">{days.map((day) => <section key={day} className="overflow-hidden rounded-2xl border border-white/10 bg-[#121512]">
    <div className="border-b border-white/10 bg-white/[.035] px-4 py-3"><p className="text-xs font-black uppercase tracking-wider text-[#e21b2d]">{day}</p><h2 className="mt-1 font-black">{rows.find((row) => row.dayName === day)?.dayTitle || "Entrenamiento"}</h2></div>
    <div className="hidden grid-cols-[minmax(180px,2fr)_70px_100px_80px_70px_80px] gap-px bg-white/10 text-sm md:grid">
      {['Ejercicio','Series','Repeticiones','Peso','RIR','Descanso'].map((label) => <div key={label} className="bg-[#181b1f] px-3 py-2 text-xs font-bold uppercase text-white/40">{label}</div>)}
      {rows.filter((row) => row.dayName === day).map((row) => <div key={row.id} className="contents">
        <button onClick={() => onExercise(row)} className="flex min-w-0 items-center gap-3 bg-[#121512] px-3 py-3 text-left hover:bg-white/5">{row.mediaPath ? <img src={row.mediaPath} alt="" className="size-11 rounded-lg bg-white object-cover" /> : <span className="size-11 rounded-lg bg-white/5" />}<span className="min-w-0"><span className="block truncate font-bold">{row.name}</span><span className="block truncate text-xs text-white/40">{row.muscle} · {row.equipment}</span></span></button>
        <Cell>{row.sets}</Cell><Cell>{row.repsMin}–{row.repsMax}</Cell><Cell>{row.targetWeight || '—'} kg</Cell><Cell>{row.targetRir}</Cell><Cell>{row.restSeconds}s</Cell>
      </div>)}
    </div>
    <div className="divide-y divide-white/8 md:hidden">{rows.filter((row) => row.dayName === day).map((row) => <button key={row.id} onClick={() => onExercise(row)} className="w-full p-4 text-left"><div className="flex items-center gap-3">{row.mediaPath ? <img src={row.mediaPath} alt="" className="size-14 rounded-xl bg-white object-cover" /> : <span className="size-14 rounded-xl bg-white/5" />}<span className="min-w-0 flex-1"><span className="block font-bold">{row.name}</span><span className="text-sm text-white/40">{row.muscle} · {row.equipment}</span></span></div><div className="mt-3 grid grid-cols-5 gap-1 text-center"><Mini label="Series" value={row.sets} /><Mini label="Reps" value={`${row.repsMin}–${row.repsMax}`} /><Mini label="Peso" value={`${row.targetWeight || '—'}kg`} /><Mini label="RIR" value={row.targetRir} /><Mini label="Desc." value={`${row.restSeconds}s`} /></div></button>)}</div>
  </section>)}</div>;
}

function Cell({ children }: { children: React.ReactNode }) { return <div className="grid place-items-center bg-[#121512] px-2 py-3 font-semibold tabular-nums">{children}</div>; }
function Mini({ label, value }: { label: string; value: React.ReactNode }) { return <span className="rounded-lg bg-white/5 px-1 py-2"><span className="block text-[10px] uppercase text-white/35">{label}</span><span className="mt-1 block text-xs font-bold tabular-nums">{value}</span></span>; }

export function RoutineSheetEditor({ catalog, rows, onChange }: { catalog: CatalogExercise[]; rows: RoutineDraftRow[]; onChange: (rows: RoutineDraftRow[]) => void }) {
  const days = [...new Set(rows.map((row) => row.dayName))];
  const weekdays = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"];
  const update = (key: string, patch: Partial<RoutineDraftRow>) => onChange(rows.map((row) => row.key === key ? { ...row, ...patch } : row));
  const addDay = () => {
    const dayName = weekdays.find((day) => !days.includes(day)) ?? weekdays[days.length % weekdays.length];
    onChange([...rows, makeRow(catalog[0]?.id ?? 0, dayName)]);
  };
  const addExercise = (dayName: string) => onChange([...rows, makeRow(catalog[0]?.id ?? 0, dayName)]);
  const renameDay = (from: string, to: string) => onChange(rows.map((row) => row.dayName === from ? { ...row, dayName: to } : row));
  const renameDayTitle = (dayName: string, dayTitle: string) => onChange(rows.map((row) => row.dayName === dayName ? { ...row, dayTitle } : row));
  return <div className="space-y-5">{days.map((day, dayIndex) => <section key={dayIndex} className="rounded-2xl border border-white/10 bg-[#111317] p-3 sm:p-4">
    <div className="mb-3 grid gap-2 sm:grid-cols-[180px_1fr_auto]"><label className="text-xs font-bold text-white/50"><span className="mb-1 block">Día</span><select value={day} onChange={(event) => renameDay(day, event.target.value)} aria-label="Día de la semana" className="h-10 w-full rounded-lg border border-white/10 bg-[#202329] px-3 font-black text-white">{weekdays.map((weekday) => <option key={weekday} value={weekday}>{weekday}</option>)}</select></label><label className="text-xs font-bold text-white/50"><span className="mb-1 block">Subtítulo del día</span><Input value={rows.find((row) => row.dayName === day)?.dayTitle ?? ""} onChange={(event) => renameDayTitle(day, event.target.value)} placeholder="Ej. Pecho y tríceps" className="h-10 border-white/10 bg-white/5 font-bold" /></label><Button type="button" onClick={() => addExercise(day)} variant="outline" className="self-end border-white/15 bg-white/5"><Plus /> Ejercicio</Button></div>
    <div className="space-y-3">{rows.filter((row) => row.dayName === day).map((row) => { const exercise = catalog.find((item) => item.id === row.exerciseId); return <div key={row.key} className="rounded-xl border border-white/10 bg-black/20 p-3">
      <div className="flex items-center gap-3">{exercise?.mediaPath ? <img src={exercise.mediaPath} alt={`Vista de ${exercise.name}`} className="size-16 shrink-0 rounded-xl bg-white object-cover" /> : <span className="size-16 shrink-0 rounded-xl bg-white/5" />}<label className="min-w-0 flex-1 text-sm font-bold">Ejercicio<select value={row.exerciseId} onChange={(event) => update(row.key, { exerciseId: Number(event.target.value) })} className="mt-1 h-10 w-full rounded-lg border border-white/10 bg-[#202329] px-3 text-white">{catalog.map((item) => <option key={item.id} value={item.id}>{item.name} · {item.muscle}</option>)}</select></label><Button type="button" onClick={() => onChange(rows.filter((item) => item.key !== row.key))} variant="ghost" size="icon" aria-label="Quitar ejercicio" className="text-white/40 hover:text-red-400"><Trash2 /></Button></div>
      <div className="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-6"><NumberField label="Series" value={row.sets} min={1} onValue={(value) => update(row.key, { sets: value })} /><NumberField label="Reps mín." value={row.repsMin} min={1} onValue={(value) => update(row.key, { repsMin: value })} /><NumberField label="Reps máx." value={row.repsMax} min={1} onValue={(value) => update(row.key, { repsMax: value })} /><NumberField label="Peso kg" value={row.targetWeight} min={0} step={2.5} onValue={(value) => update(row.key, { targetWeight: value })} /><NumberField label="RIR" value={row.targetRir} min={0} max={10} onValue={(value) => update(row.key, { targetRir: value })} /><NumberField label="Desc. seg" value={row.restSeconds} min={0} step={15} onValue={(value) => update(row.key, { restSeconds: value })} /></div>
    </div>; })}</div>
  </section>)}<Button type="button" onClick={addDay} variant="outline" className="w-full border-dashed border-white/20 bg-white/[.025]"><Plus /> Agregar día</Button></div>;
}

function NumberField({ label, value, min, max, step = 1, onValue }: { label: string; value: number; min: number; max?: number; step?: number; onValue: (value: number) => void }) { return <label className="text-xs font-bold text-white/50"><span className="mb-1 block">{label}</span><Input type="number" value={value} min={min} max={max} step={step} onChange={(event) => onValue(numberValue(event.target.value, min))} className={inputClass} /></label>; }

export function makeRow(exerciseId: number, dayName = "Lunes"): RoutineDraftRow { return { key: crypto.randomUUID(), exerciseId, dayName, dayTitle: "", sets: 3, repsMin: 8, repsMax: 12, targetWeight: 0, targetRir: 3, restSeconds: 90 }; }
