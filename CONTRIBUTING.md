# Guía de colaboración (sin Live Share)

Este proyecto usa Git y GitHub. Cada colaborador ejecuta Godot localmente en su PC.

## Requisitos
- Git instalado (Windows: https://git-scm.com/download/win)
- Godot 4.4.1 instalado o el ejecutable en la carpeta del repo

## Primera vez (cada colaborador)
```powershell
# Clonar
git clone https://github.com/edyangel/Rise-of-Ages.git
cd Rise-of-Ages

# Configurar identidad (reemplaza tus datos)
git config --global user.name "Tu Nombre"
git config --global user.email "tu-email@example.com"
```

## Abrir Godot
- Si el ejecutable está en la raíz del repo:
  ```powershell
  .\Godot_v4.4.1-stable_win64.exe --editor
  ```
- Si Godot 4.4.1 está en PATH:
  ```powershell
  godot --editor --path .
  ```

## Ciclo de trabajo diario
1. Traer lo último de main
   ```powershell
   git checkout main
   git pull
   ```
2. Crear una rama para tu tarea
   ```powershell
   git checkout -b feat/mi-tarea
   ```
3. Trabajar y probar en Godot
4. Guardar y publicar cambios
   ```powershell
   git add .
   git commit -m "feat: describe tu cambio"
   git push -u origin feat/mi-tarea
   ```
5. Abrir Pull Request en GitHub y pedir revisión

## Mantener tu rama actualizada
```powershell
git pull --rebase origin main
```

## Después del merge a main
```powershell
git checkout main
git pull
git branch -d feat/mi-tarea
# opcional: borrar la rama remota
# git push origin --delete feat/mi-tarea
```

## Resolver conflictos (rápido)
1. VS Code mostrará conflictos con marcadores `<<<<`, `====`, `>>>>`.
2. Elige “Accept Current/Incoming/Both” según corresponda.
3. Luego:
   ```powershell
   git add .
   # si estabas en rebase
   git rebase --continue
   # o si estabas en merge
   # git commit
   ```

## Reglas rápidas
- Usa Godot 4.4.1 para evitar cambios de formato del proyecto.
- Commits pequeños y frecuentes; pull frecuente.
- Evita editar las mismas líneas que otra persona.
- `.godot/` y `.import/` están ignorados; no subas ejecutables nuevos.
