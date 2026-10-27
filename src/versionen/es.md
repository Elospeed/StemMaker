# Historial de versiones

Versión corta para la pestaña «Versiones» de la ventana Info, la más reciente arriba.
Se incluye en StemMaker.exe. En cada release añadir una sección «## <versión> – <fecha>»
aquí, en de.md y en en.md (el workflow de release lo comprueba).
Solo lo que notan los usuarios, breve y sin detalles técnicos.

## 2.0 – 26 de octubre de 2026
- Nuevo motor Turbo: los stems se separan en la CPU unas 6 a 10 veces más rápido, con la misma calidad
- Con una tarjeta gráfica adecuada (NVIDIA, AMD, Intel) solo tarda segundos por canción (beta)
- Una breve prueba previa al primer inicio mide la CPU y la tarjeta gráfica e indica cuánto tardará una canción
- El motor anterior se puede seguir eligiendo y entra automáticamente si Turbo falla con un archivo
- Las mezclas largas de DJ necesitan mucha menos memoria

## 1.9 – 23 de octubre de 2026
- StemMaker ya está disponible también en español (gracias a David GJ por la traducción)
- Nueva pestaña «Gracias» en «Info» con todos los que han ayudado
- StemPlayer: bucle A-B, una sección se repite sin cortes
- StemPlayer: lupa para ajustar el bucle con precisión, con rejilla de tiempo y zoom
- StemPlayer: scrubbing, al arrastrar la onda se oye el sonido como en un vinilo
- StemPlayer ahora habla alemán, inglés y español (según el idioma de StemMaker)

## 1.8.1 – 20 de octubre de 2026
- El título, artista, álbum y BPM de archivos OGG y Opus ahora pasan al archivo stem
- El título de la ventana dice «de archivos de audio» en lugar de «de MP3»

## 1.8 – 18 de octubre de 2026
- Ventana principal con color: barra de progreso en la lista, marca de verificación y puntos de color de los stems en los archivos terminados
- StemPlayer 1.5: forma de onda por stem, solo como en un mezclador de DJ
- «Convertir de nuevo» realmente vuelve a convertir, las canciones canceladas ya no cuentan como errores
- El archivo stem existente ya no se pierde al sobrescribir
- Muchas pequeñas correcciones

## 1.7.1 – 14 de octubre de 2026
- Nueva ventana «Más ajustes» (icono de engranaje)
- Icono junto al reloj: progreso y aviso cuando todo ha terminado
- Botón «Colores de Traktor» para los colores de los stems
- Instalador (Setup.exe) además del ZIP
- Enviar informe de errores (solo si quieres, no se envía nada automáticamente)
- Parada limpia al apagar Windows, mensaje claro con rutas demasiado largas
- StemPlayer 1.4 y descargas más seguras

## 1.7 – 6 de octubre de 2026
- «Escuchar» en StemPlayer y «Abrir carpeta después de la conversión»
- Nivel club (normalizar sonoridad) y Bass fix
- BPM, tonalidad, sello e ISRC se copian al archivo stem
- Búsqueda de actualizaciones al iniciar y «Buscar actualizaciones» en la ventana Info
- StemPlayer 1.3 con el diseño «Traktor Dark», con silencio, solo y fader por stem
- Muchos errores corregidos

## 1.6 – 2 de octubre de 2026
- Primera versión pública en GitHub
- Convertir colecciones enteras, la lista continúa tras un fallo o un reinicio
- Apagar el PC al terminar (con cuenta atrás)
- Alemán e inglés
- Las diéresis y acentos en los nombres de archivo funcionan en todas partes

## 1.5
- El PC no entra en reposo durante la conversión, el plan de energía se pone temporalmente en alto rendimiento
- Nuevo icono del programa y nuevo nombre «Elospeed StemMaker»

## 1.4
- Se usan todos los núcleos del procesador, unas dos veces más rápido en PCs antiguos

## 1.0 – 1.3
- Los archivos de audio se convierten en archivos stem de Traktor con master, drums, bass, other y vox
- La ventana de inicio lo comprueba todo y descarga ffmpeg y el modelo de separación automáticamente
- StemCLI como versión de línea de comandos
