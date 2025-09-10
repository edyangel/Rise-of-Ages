Rise of Ages — Proyecto Godot 4.4.1

Cómo ejecutar (Windows, PowerShell):
1) Editor:
	- Doble clic a `Godot_v4.4.1-stable_win64.exe` y abre esta carpeta, o
	- Terminal en la carpeta del proyecto:
	  - `./Godot_v4.4.1-stable_win64.exe --editor`
2) Ejecutar el juego:
	- `./Godot_v4.4.1-stable_win64.exe --path .`
3) En el editor, F5 ejecuta la escena principal (`res://scenes/main.tscn`).

VS Code (opcional):
- Usa Tareas: Ctrl+Shift+P → “Run Task” → “Godot: Editor” o “Godot: Run”.
- Archivo `.vscode/tasks.json` ya configurado para el ejecutable incluido.

Setup para colaboradores:
1) Instalar Git: https://git-scm.com/download/win
2) Clonar:
	- `git clone https://github.com/edyangel/Rise-of-Ages.git`
	- `cd Rise-of-Ages`
3) Godot:
	- Usa `Godot_v4.4.1-stable_win64.exe` del repo, o instala Godot 4.4.1 y añade a PATH.
4) Abrir/ejecutar con tareas de VS Code o comandos arriba.

Flujo de trabajo con Git:
- Traer cambios: `git pull`
- Crear rama: `git checkout -b feat/mi-tarea`
- Commit/push:
  - `git add .`
  - `git commit -m "feat: describe tu cambio"`
  - `git push -u origin feat/mi-tarea`
- Abre un Pull Request en GitHub y pide revisión.

Notas:
- Usa exactamente Godot 4.4.1 para evitar diferencias de proyecto.
- `.gitignore` ya excluye caches (`.godot/`, `.import/`) y ejecutables.
