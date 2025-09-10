PROJECT PROMPT

Usa este archivo como el "prompt persistente" del proyecto: edítalo para cambiar la visión y las restricciones; yo lo leeré al inicio de cada trabajo en este repositorio.

Resumen del proyecto
- Nombre: RTS (working title)
- Género: RTS en tiempo real, estilo Age of Empires (partidas con unidades, construcciones, recursos).
- Motores/tecnología: Godot 4.4 (GDScript por defecto), export: Android/iOS/PC.
- Multijugador: servidor autoritativo (ENet/UDP) con comando por tick y snapshots; inicio: LAN/ENet prototipo.

Visión online persistente
- El juego es online y las partidas no tienen un "final" tradicional: los imperios crecen continuamente (más territorio, más unidades, más estructuras). Cuando un jugador pierde todas sus unidades en una región/servidor, queda eliminado en ese frente, pero el mundo persistente continúa. El objetivo es construir y expandir tu imperio a largo plazo en un universo compartido.
- Esta persistencia implica arquitecturas de servidor que soporten estado continuo (sharding/zonas), guardado periódico, y sistemas anti-exploit/recuperación.

Estilo artístico
- Referencia gráfica: estética tipo Red Alert / Age of Empires clásica pero con estilo único.
- Unidades pixel: reglas fijas de tamaño/poses: cabeza 1px, torso 3px, brazos/piernas consistentes. Se puede usar más pixeles manteniendo el mismo espacio y proporciones.

Requisitos funcionales iniciales (prioridad)
1. Menú principal y navegación (ya creado). 
2. Escena de creación de unidades (editor de apariencia, obligar a mantener la misma caja/poses). 
3. Prototipo single-player: selección de unidades, movimiento, pathfinding simple. 
4. Prototipo LAN con ENet (autoridad simple). 

Convenciones del repo
- Main scene: `res://scenes/menu.tscn`
- Scripts en `res://scripts/` (GDScript)
- Escenas en `res://scenes/`
- Actúa sobre estas rutas cuando agregues sistemas.

Notas sobre la persistencia y móvil
- Modo online persistente requiere: gestión de sesiones largas, sincronización eventual entre regiones, interest management para reducir ancho de banda y persistencia en base de datos.
- El juego target es móvil y desktop; diseño de UI y optimizaciones deben priorizar baja latencia y uso eficiente de batería/datos en móviles.

Notas para el asistente
- Antes de hacer cambios, lee este archivo para alinear decisiones con la visión.
- Si el usuario cambia la especificación, prioriza la nueva versión.

Cómo usarlo
- Edítalo en el repo para cambiar la visión/alcance.
- Pide explícitamente: "lee el prompt del proyecto" cuando quieras que aplique cambios basados en él.
