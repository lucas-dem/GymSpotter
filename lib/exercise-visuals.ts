export type ExerciseVisual = {
  src: string;
  frameOrder?: readonly [number, number, number];
  cues: readonly [string, string, string];
};

export const exerciseVisuals: Record<string, ExerciseVisual> = {
  "press-banca": {
    src: "/exercises/press-banca-steps.png",
    frameOrder: [2, 1, 0],
    cues: ["Barra arriba, pies apoyados y escápulas juntas.", "Bajá la barra con control, sin abrir demasiado los codos.", "Acercá la barra al pecho sin rebotar; empujá para volver."],
  },
  "press-inclinado": {
    src: "/exercises/press-inclinado-steps.png",
    frameOrder: [2, 1, 0],
    cues: ["Apoyá la espalda en el banco inclinado y sostené la barra arriba.", "Bajá con control hacia la parte superior del pecho.", "Desde abajo, empujá la barra manteniendo los pies firmes."],
  },
  "aperturas-polea": {
    src: "/exercises/aperturas-polea-steps.png",
    cues: ["Abrí los brazos con los codos apenas flexionados.", "Acercá las manos en un arco, manteniendo el torso estable.", "Juntá las manos delante del cuerpo y volvé con control."],
  },
  "extension-triceps": {
    src: "/exercises/extension-triceps-steps.png",
    cues: ["Sostené el agarre con los codos flexionados y pegados al cuerpo.", "Empujá hacia abajo sin mover los brazos desde el hombro.", "Extendé los codos y dejá subir el agarre con control."],
  },
  sentadilla: {
    src: "/exercises/sentadilla-steps.png",
    cues: ["Apoyá la barra sobre la espalda alta y afirmá el torso.", "Flexioná caderas y rodillas, con los pies apoyados.", "Llegá a una profundidad controlada y empujá el suelo para subir."],
  },
  "remo-polea": {
    src: "/exercises/remo-polea-steps.png",
    cues: ["Sentate con los pies apoyados y los brazos extendidos.", "Llevá los codos hacia atrás sin balancear el torso.", "Acercá el agarre al abdomen y extendé los brazos con control."],
  },
};

// Reverse through the middle pose instead of jumping from the end to the start.
export const exercisePlayback = [0, 1, 2, 1] as const;
