# Historial de versiones

Versión corta para la pestaña «Versiones» de la ventana Info, la más reciente arriba.
Se incluye en StemMaker.exe. En cada release añadir una sección «## <versión> – <fecha>»
aquí, en de.md y en en.md (el workflow de release lo comprueba).
Debajo «### Nuevo», «### Mejorado», «### Corregido» (solo los que haya), una palabra
clave breve por punto. Solo lo que notan los usuarios, sin detalles técnicos.

## 2.1.2 – aún no publicada
### Corregido
- StemPlayer 1.8.2: reproductor de CD cortado abajo con escalado del 125 % (botón Ko-fi, MASTER)

## 2.1.1 – 30 de octubre de 2026
### Corregido
- Con escalado de pantalla del 150 % y 200 % las ventanas eran más altas que la pantalla (ventana principal, ajustes, StemDecks)
- Selección de idioma, ventana de actualización y pregunta antes de apagar demasiado pequeñas con escalado
- Botón Ko-fi demasiado ancho al 150 %
- StemTagger 1.0.1: columnas de la lista demasiado estrechas con escalado
- StemPlayer 1.8.1: ventana con escalado del 125–200 % (altura ajustable, reproductor de CD correcto, barra de desplazamiento en pantallas pequeñas)

## 2.1 – 29 de octubre de 2026
### Nuevo
- StemTagger 1.0: título, artista, álbum, género y portada en archivos stem, también para muchos archivos a la vez
- Barra de AddOns junto a la lista de archivos: StemPlayer y StemTagger con un clic
- StemPlayer 1.8: nueva vista Reproductor de CD con jog wheel y pads de stems
- Pestaña «Versiones» en la ventana Info
- Menú contextual en la lista de archivos: Escuchar, Editar etiquetas, Quitar de la lista (también tecla Supr)
### Mejorado
- «Escuchar» reproduce directamente el archivo terminado
- Ya no se abre el Explorador tras la conversión (se puede activar)
### Corregido
- La ventana principal crecía en cada inicio con escalado de pantalla superior al 100 %
- StemPlayer: lupa cortada con escalado de pantalla al 150 % y 200 %

## 2.0 – 26 de octubre de 2026
### Nuevo
- Motor Turbo: stems unas 6 a 10 veces más rápido en la CPU, misma calidad
- Tarjeta gráfica (NVIDIA, AMD, Intel): solo segundos por canción (beta)
- Prueba previa al primer inicio: mide la CPU y la tarjeta gráfica, predice el tiempo por canción
### Mejorado
- El motor anterior se puede seguir eligiendo, entra automáticamente si Turbo falla
- Las mezclas largas de DJ necesitan mucha menos memoria
- El registro muestra el motor usado en cada archivo

## 1.9 – 23 de octubre de 2026
### Nuevo
- Español (traducción: David GJ)
- Pestaña «Gracias» en la ventana Info
- StemPlayer: bucle A-B, sin cortes
- StemPlayer: lupa con rejilla de tiempo y zoom para ajustar el bucle con precisión
- StemPlayer: scrubbing como en un vinilo
### Mejorado
- StemPlayer en alemán, inglés y español (según el idioma de StemMaker)

## 1.8.1 – 20 de octubre de 2026
### Corregido
- Faltaban las etiquetas (título, artista, álbum, BPM) de OGG y Opus en el archivo stem
- Título de la ventana: «de archivos de audio» en lugar de «de MP3»

## 1.8 – 18 de octubre de 2026
### Nuevo
- Ventana principal con color: barra de progreso en la lista, marca de verificación y puntos de color de los stems
- StemPlayer 1.5: forma de onda por stem, vista compacta/forma de onda
### Mejorado
- StemPlayer: solo como en un mezclador de DJ
### Corregido
- «Convertir de nuevo» se saltaba todos los archivos
- Las canciones canceladas contaban como errores
- El archivo stem existente podía perderse al sobrescribir
- La lista sobrevive a un corte de luz al guardar
- Varias correcciones pequeñas

## 1.7.1 – 14 de octubre de 2026
### Nuevo
- Ventana «Más ajustes» (icono de engranaje)
- Icono junto al reloj con progreso y aviso al terminar
- Botón «Colores de Traktor»
- Instalador (Setup.exe) además del ZIP
- Enviar informe de errores (solo a mano, nada automático)
### Mejorado
- Descargas más seguras (sumas de comprobación integradas)
- Mensaje claro con rutas de más de 260 caracteres
- StemPlayer 1.4: rechaza archivos incorrectos con un mensaje claro
### Corregido
- Apagar Windows durante una conversión: ahora se detiene limpiamente
- Número de versión incorrecto en «Aplicaciones y características» tras una actualización

## 1.7 – 6 de octubre de 2026
### Nuevo
- «Escuchar» en StemPlayer
- «Abrir carpeta después de la conversión»
- Nivel club (normalizar sonoridad) y Bass fix
- Búsqueda de actualizaciones al iniciar y «Buscar actualizaciones»
- StemPlayer 1.3: diseño «Traktor Dark», silencio, solo y fader por stem
### Mejorado
- Etiquetas: también BPM, tonalidad, sello e ISRC
- Versión fija de ffmpeg con suma de comprobación
- Registro con sonoridad y velocidad, archivo statistik.csv
### Corregido
- A veces StemMaker no se podía cerrar
- Se perdían archivos con el mismo nombre de carpetas distintas
- demucs seguía calculando en segundo plano tras un fallo

## 1.6 – 2 de octubre de 2026
### Nuevo
- Primera versión pública en GitHub
- Convertir colecciones enteras, la lista continúa tras un fallo o un reinicio
- Apagar el PC al terminar (con cuenta atrás)
- Alemán e inglés
### Corregido
- Diéresis y acentos en los nombres de archivo (p. ej. «Tiësto»)
- StemCLI no leía StemMaker.ini

## 1.5
### Nuevo
- El PC no entra en reposo durante la conversión
- Nuevo icono del programa, nuevo nombre «Elospeed StemMaker»
### Mejorado
- Plan de energía en alto rendimiento durante la conversión (aprox. 8 % más rápido)
- La tasa de bits AAC se adapta a la fuente

## 1.4
### Mejorado
- Se usan todos los núcleos del procesador, unas dos veces más rápido en PCs antiguos
- Mejor estimación del tiempo restante

## 1.0 – 1.3
### Nuevo
- Archivos de audio a archivos stem de Traktor (master, drums, bass, other, vox)
- La ventana de inicio descarga ffmpeg y el modelo de separación automáticamente
- StemCLI para la línea de comandos
