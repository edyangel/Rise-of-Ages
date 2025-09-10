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

> Error común al clonar
>
> fatal: destination path 'Rise-of-Ages' already exists and is not an empty directory.
>
> Soluciones rápidas (elige una):
> - Ya lo tienes clonado: entra y actualiza
>   ```powershell
>   cd Rise-of-Ages
>   git pull
>   ```
> - Clonar con otro nombre de carpeta
>   ```powershell
>   git clone https://github.com/edyangel/Rise-of-Ages.git Rise-of-Ages-2
>   ```
> - Si la carpeta existe pero no es repo (o está vacía), borra/mueve la carpeta y vuelve a clonar.
> - Avanzado: convertir carpeta existente en repo remoto
>   ```powershell
>   cd Rise-of-Ages
>   git init
>   git remote add origin https://github.com/edyangel/Rise-of-Ages.git
>   git fetch
>   git switch -c main --track origin/main
>   ```

## Abrir Godot
- Si el ejecutable está en la raíz del repo:
  ```powershell
  .\Godot_v4.4.1-stable_win64.exe --editor
  ```
- Si Godot 4.4.1 está en PATH:
  ```powershell
  godot --editor --path .
  ```

> ¿Error: "No se encontró el ejecutable Godot_v4.4.1-stable_win64.exe"?
>
> El repo no incluye Godot. Opciones:
> - Usa Godot desde PATH (recomendado): instala Godot 4.4.1 (Standard, no .NET salvo que lo necesites), agrega godot.exe al PATH y prueba `godot --version`. Luego:
>   ```powershell
>   godot --editor --path .
>   ```
> - Descarga el ejecutable portátil de Godot 4.4.1 para Windows y colócalo en la raíz del repo con el nombre `Godot_v4.4.1-stable_win64.exe` (o actualiza el comando con el nombre real del archivo) y ejecútalo como arriba.
> - Alternativa: abre el lanzador de Godot, haz "Import/Scan" y selecciona el archivo `project.godot` de este repo.

> ¿Ves una versión vieja del juego tras clonar/actualizar?
>
> Causas típicas: estás en otra carpeta/fork, rama distinta a `main`, tu repo local no está actualizado o Godot está usando caché viejo.
> Pasos rápidos (ejecútalos en la carpeta que contiene `project.godot`):
> 1) Verifica el remoto y la carpeta
>   ```powershell
>   git remote -v
>   git rev-parse --show-toplevel
>   ```
>   Asegúrate que `origin` apunta a `https://github.com/edyangel/Rise-of-Ages.git` y que estás en la carpeta correcta.
> 2) Trae y cambia a main
>   ```powershell
>   git fetch --all --prune
>   git switch main
>   git pull
>   git log --oneline -n 3
>   ```
> 3) Si hay cambios locales que bloquean el pull
>   - O guarda temporalmente: `git stash -u`
>   - O fuerza alineación (destructivo):
>     ```powershell
>     git reset --hard origin/main
>     ```
> 4) Forzar reimport en Godot (por caché)
>   - Cierra Godot.
>   - Borra las carpetas `.godot/` y `.import/` (si existen).
>   - Vuelve a abrir el proyecto.
> 5) Asegura versión de Godot
>   - Usa Godot 4.4.1 (Standard). O abre el proyecto con `godot --editor --path .`.
> 6) Último recurso
>   - Si clonaste un ZIP viejo o un fork: borra la carpeta y clona de nuevo el repo oficial.

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
