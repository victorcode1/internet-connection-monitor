# internet_connection_monitor

Una librería para que tu app sepa cuándo tiene Internet, cuándo lo pierde y cuándo vuelve.
Puedes usarla en proyectos Dart y Flutter.

[Ver cómo funciona](https://victorf.dev/projects/internet-connection-monitor) ·
[Instalar desde pub.dev](https://pub.dev/packages/internet_connection_monitor) ·
[Ver el código en GitHub](https://github.com/victorcode1/internet-connection-monitor)

## ¿Para qué sirve?

Tener Wi-Fi no siempre significa tener Internet. Esta librería comprueba la
conexión y le avisa a tu app cuando cambia.

Tu app puede usar esa respuesta para mostrar un mensaje de **«Sin Internet»**,
ofrecer un botón **«Reintentar»** o esperar antes de volver a enviar información.
Tú decides qué mensaje mostrar y qué hacer después.

## ¿Cómo funciona?

1. Tu app pide revisar la conexión.
2. La librería intenta obtener una respuesta de Internet. Si la primera dirección
   falla, prueba otra.
3. Tu app recibe el resultado y puede avisarle al usuario.

Por defecto, espera dos revisiones fallidas seguidas antes de confirmar que no
hay Internet. Así evita avisar por un fallo pasajero. También sigue revisando
para detectar cuándo vuelve la conexión.

## Instalación

Dentro de un proyecto Dart, ejecuta:

```sh
dart pub add internet_connection_monitor
```

Si trabajas con Flutter, usa:

```sh
flutter pub add internet_connection_monitor
```

También puedes añadirla a tu archivo `pubspec.yaml`:

```yaml
dependencies:
  internet_connection_monitor: ^0.1.2
```

## Un ejemplo para empezar

Este código muestra los avisos en español. Puedes guardarlo en `bin/main.dart`
de un proyecto de consola Dart y ejecutarlo con `dart run bin/main.dart`.

```dart
import 'package:internet_connection_monitor/internet_connection_monitor.dart';

String mensajeDeConexion(InternetStatus estado) {
  switch (estado) {
    case InternetStatus.unknown:
      return 'Revisando';
    case InternetStatus.online:
      return 'Con Internet';
    case InternetStatus.offline:
      return 'Sin Internet';
  }
}

Future<void> main() async {
  final monitor = InternetConnectionMonitor();
  final avisos = monitor.changes.listen((estado) {
    print(mensajeDeConexion(estado));
  });

  try {
    print(mensajeDeConexion(monitor.status));
    await monitor.start();

    // Esta demostración permanece activa durante 10 segundos.
    await Future<void>.delayed(const Duration(seconds: 10));

    // Puedes usar esta llamada en un botón «Reintentar».
    await monitor.check();
  } finally {
    // Al terminar, deja de escuchar avisos y detén las revisiones.
    await avisos.cancel();
    await monitor.dispose();
  }
}
```

Al empezar verás **«Revisando»**. Después aparecerá **«Con Internet»** o
**«Sin Internet»** cuando se confirme el resultado.
Si la respuesta no cambia, la librería no repite el mismo aviso.

El ejemplo termina después de esperar 10 segundos y hacer una última revisión.
En una app, deja el monitor activo mientras lo necesites y detenlo cuando ya no
lo vayas a usar.

## Las llamadas que vas a usar

| Llamada                       | Qué hace                                                             |
| ----------------------------- | -------------------------------------------------------------------- |
| `monitor.start()`             | Empieza a revisar la conexión y sigue haciéndolo cada cierto tiempo. |
| `monitor.changes.listen(...)` | Recibe un aviso cuando cambia la respuesta.                          |
| `monitor.status`              | Te dice la última respuesta conocida.                                |
| `monitor.check()`             | Pide revisar otra vez, por ejemplo al tocar «Reintentar».            |
| `monitor.dispose()`           | Detiene el monitor cuando terminas de usarlo.                        |

Los nombres que aparecen en el código significan lo siguiente:

| Nombre en el código | En palabras sencillas                                                             |
| ------------------- | --------------------------------------------------------------------------------- |
| `unknown`           | Todavía no sabemos si hay conexión.                                               |
| `online`            | Al menos una dirección de Internet respondió como se esperaba.                    |
| `offline`           | Las revisiones fallaron las veces necesarias para confirmar la falta de conexión. |

## ¿Puedo usarla en Flutter?

Sí. Puedes mostrar los avisos en tus pantallas y elegir cómo reaccionan tus botones.
La librería no trae pantallas ni te obliga a usar una forma concreta de organizar tu app.

## Qué significa tener Internet en esta librería

La respuesta indica si alguna de las direcciones consultadas respondió como se
esperaba. Un sitio concreto puede seguir fallando aunque la respuesta sea
**«Con Internet»**.

Si una red bloquea las direcciones de revisión, el resultado puede ser
**«Sin Internet»** aunque otros sitios sí funcionen. Puedes elegir las direcciones
que se revisan para adaptarlas a tu app.

<details>
<summary><strong>Más opciones, si las necesitas</strong></summary>

### Cada cuánto vuelve a revisar

Estos son los valores de inicio. Puedes cambiarlos al crear el monitor.

| Situación                                   | Cuándo vuelve a revisar | Opción en el código |
| ------------------------------------------- | ----------------------- | ------------------- |
| La primera revisión falló y falta confirmar | Después de 2 segundos   | `confirmationDelay` |
| Se confirmó que no hay Internet             | Después de 10 segundos  | `retryInterval`     |
| Hay Internet                                | Después de 30 segundos  | `onlineInterval`    |

Los tiempos empiezan a contar **cuando termina la revisión anterior**.
Cada dirección puede tardar hasta 4 segundos en responder. Una revisión completa
se limita a 10 segundos con `checkTimeout`. Por eso, detectar un cambio puede
tardar más que el tiempo de espera de la tabla.

`failureThreshold` permite elegir cuántas revisiones fallidas seguidas hacen
falta para avisar que no hay conexión. El valor de inicio es `2`.

### Elegir otra dirección para revisar

Por defecto se prueban direcciones de Google y Cloudflare. Se espera una
respuesta con el código `204`, que indica una respuesta correcta sin contenido.
Una página de inicio de sesión del Wi-Fi no cuenta como esa respuesta.

Puedes usar una dirección propia y elegir qué respuesta debe devolver. Este
bloque es un ejemplo completo; cambia `tu-dominio.example` por tu dirección
antes de ejecutarlo.

```dart
import 'package:internet_connection_monitor/internet_connection_monitor.dart';

Future<void> main() async {
  final comprobacion = HttpInternetProbe(
    endpoints: [
      InternetCheckEndpoint(
        Uri.https('tu-dominio.example', '/health'),
        method: 'HEAD',
        expectedStatusCode: 200,
      ),
    ],
  );
  final monitor = InternetConnectionMonitor(probe: comprobacion.call);

  try {
    await monitor.start();
    print(monitor.status.name);
  } finally {
    await monitor.dispose();
    comprobacion.close();
  }
}
```

En este ejemplo, `HEAD` pide una respuesta sin descargar el contenido y `200`
es el código que esperamos recibir. También puedes usar `GET` si tu dirección
lo necesita. La librería acepta la respuesta exacta que hayas elegido; una
redirección a otra página no cuenta como una respuesta válida.

Si pasas tu propia comprobación mediante `probe`, tú te encargas de cerrarla,
como hace `comprobacion.close()` en el ejemplo. Si usas `clientFactory`, devuelve
un cliente nuevo en cada llamada: la librería cerrará cada uno al terminar.

Una comprobación propia debe limitar cuánto espera. El monitor puede dejar de
esperar su resultado, pero no puede detener por sí solo una operación que hayas
creado fuera de la librería.

### Recibir los avisos en Flutter

Empieza a escuchar los avisos antes de llamar a `start()`, como en el ejemplo.
Si empiezas a escucharlos después, lee también `monitor.status`: los avisos
anteriores no se vuelven a enviar. Si usas `StreamBuilder`, puedes pasarle
`initialData: monitor.status` para que tenga una respuesta inicial.

Cuando la app vuelva a estar en pantalla, llama a `monitor.check()` desde la
parte de tu código que detecta ese regreso. La librería no lo hace por sí sola.
Si ya detectas cambios de Wi-Fi en tu app, puedes enviar esos avisos mediante
`networkChanges` para pedir otra revisión. Detectar Wi-Fi sigue sin demostrar
que haya Internet.

### Algunas cosas a tener en cuenta

- Puedes llamar a `start()` varias veces: no crea revisiones repetidas.
- Si llamas a `check()` sin llamar antes a `start()`, haces una sola revisión;
  no se activa la revisión periódica.
- Las revisiones se hacen una detrás de otra. Si se pide una nueva mientras hay
  otra en marcha, se descarta el resultado anterior y se hace una nueva.
- Después de `dispose()`, crea un monitor nuevo si quieres empezar otra vez.
- Cancela los avisos que escuchas antes de esperar a que termine `dispose()`.
  Si has pausado un oyente, reanúdalo o cancélalo para que el cierre pueda terminar.

### Uso en páginas web y otras apps

En una página web, la dirección consultada debe permitir recibir solicitudes
desde tu página. Este permiso se llama **CORS**. Si falta, el navegador puede
bloquear la revisión. Usa direcciones `https` cuando tu página también use `https`.
Una respuesta que el navegador no permite leer tampoco confirma la conexión.

En apps móviles y de computadora, asegúrate de que tu app tenga permiso para
usar Internet. El sistema puede pausar las revisiones mientras la app no esté
en uso; pide otra revisión cuando vuelva a estar en pantalla.

</details>

## Si quieres colaborar

Puedes [contar un problema o proponer una mejora](https://github.com/victorcode1/internet-connection-monitor/issues).
La librería se puede usar y compartir con la [licencia MIT](LICENSE).

Para revisar los cambios en tu computadora:

```sh
dart pub get
dart format --output=none --set-exit-if-changed lib test example
dart analyze
dart test
dart pub publish --dry-run
```

El último comando revisa lo que se publicaría, sin subirlo a pub.dev.
La publicación real se hace con `dart pub publish`.
Puedes consultar la [guía oficial de publicación](https://dart.dev/tools/pub/publishing).
