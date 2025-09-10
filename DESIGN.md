Rediseño - Resumen y roadmap

Objetivo: construir un RTS con look clásico (AoE/Red Alert) y arte píxel coherente, con soporte móvil y multijugador autoritativo.

1) Sistemas centrales
- Input & Selection: selección con clic/arrastre, selección múltiple, orden por comando.
- Movimiento & Pathfinding: grid lógico + flow field para grupos; A* para bots individuales en prototipo.
- Simulación y autoridad: servidor aplica comandos por tick (10-20 TPS), clientes envían comandos y realizan predicción local.
- Entidades/Componentes: entidad con componentes (Transform, Render, Physics, CommandQueue, Health).
- Recursos: pickups (oro) y árboles (madera) con recolección por trabajadores.

2) Networking (prototipo)
- Protocolo: ENet (UDP). Mensajes: PlayerCommand(cmd, unit_id[], params), Snapshot(diff).
- Tick loop: server procesa comandos por tick, envía diffs; clients reconcilian.

3) Arte y animación
- Especificación de spritesheet: caja fija por unidad (p.ej. 24x24 px), pero los pixeles del personaje respetan la regla 1px cabeza, 3px torso.
- Paleta limitada y documentación de tamaños/poses para el editor de creación.

4) UX móvil
- Controles: selección por toque/arrastre, cámara por arrastre con dos dedos o borde, botones grandes para acciones.
- Optimización: instancing, culling, reducir partículas y overdraw.

5) Milestones iniciales (MVP)
- M1 (1-2 días): Menú + escena juego + placeholders (hecho parcialmente).
- M2 (3-5 días): Selección y movimiento local (click/arrastre, pathfinding simple).
- M3 (4-7 días): Sistema de recursos (árboles, oro) y trabajadores básicos.
- M4 (1-2 semanas): Prototipo multijugador LAN autoritativo (ENet).

6) Datos y contratos (ejemplo)
- PlayerCommand: {tick:int, player_id:int, cmd_type:string, target_pos:Vector2, unit_ids:PoolIntArray}
- UnitState snapshot: {id:int, pos:Vector2, facing:float, hp:int, action:string}

Siguientes acciones recomendadas
- Elegir la tarea a implementar ahora: (A) selección+movimiento local, (B) editor de creación visual, (C) colocar assets de referencia para la paleta píxel.
- Yo puedo implementar (A) inmediatamente: crear escena `battlefield.tscn`, unidades instanciables, selección y movimiento.
