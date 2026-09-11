# GymSpotter

GymSpotter reúne membresías, rutinas y seguimiento entre socios, entrenadores y administradores de gimnasio.

## MVP actual

- Panel responsive para socio, entrenador y administrador.
- Estado y renovación persistente de membresía.
- Rutina semanal, entrenamiento serie por serie y demostraciones animadas del catálogo que utiliza openGym.
- Registro de peso, entrenamientos, cargas, repeticiones y RIR.
- Creador de rutinas con biblioteca de ejercicios.
- Gestión de alumnos y asignación persistente de rutinas.
- Panel del gimnasio con socios, vencimientos, ocupación e ingresos.
- Mapa anatómico frontal y posterior con fatiga calculada desde las series registradas en los últimos 7 días.
- Acciones demostrables con notificaciones y soporte WebMCP.

Los datos principales se almacenan en Cloudflare D1 y cada escritura se vincula al usuario autenticado por la plataforma.

## Desarrollo local

Requiere Node.js 22.13 o superior.

```bash
npm install
npm run dev
```

La aplicación estará disponible en `http://localhost:5173`.

## Producción

```bash
npm run build
npm start
```

## Tecnología

React 19, TypeScript, Tailwind CSS, Vinext/Vite, Cloudflare D1, Drizzle y componentes accesibles basados en Radix UI.

## Recursos y atribuciones

El mapa muscular utiliza la geometría SVG de MuscleMap (MIT) convertida por openGym. Las demostraciones se cargan, como en la versión demo de openGym, desde `hasaneyldrm/exercises-dataset`; no se almacenan copias dentro de este repositorio. Consultá [NOTICE.md](NOTICE.md) antes de redistribuir estos recursos.
