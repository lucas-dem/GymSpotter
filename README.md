# GymSpotter

GymSpotter reúne membresías, rutinas y seguimiento entre socios, entrenadores y administradores de gimnasio.

## MVP actual

- Panel responsive para socio, entrenador y administrador.
- Estado y renovación persistente de membresía.
- Rutina semanal, entrenamiento serie por serie y explicación visual de ejercicios.
- Registro de peso, entrenamientos, cargas, repeticiones y RIR.
- Creador de rutinas con biblioteca de ejercicios.
- Gestión de alumnos y asignación persistente de rutinas.
- Panel del gimnasio con socios, vencimientos, ocupación e ingresos.
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

## Licencia

Código propio de GymSpotter. El proyecto no incorpora código ni recursos multimedia de openGym.
