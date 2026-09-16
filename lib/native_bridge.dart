import 'package:flutter/services.dart';

class NativeBridge {
  static const channel = MethodChannel('id.sahabatnetra/control');
  static const events = EventChannel('id.sahabatnetra/events');

  Stream<Map<Object?, Object?>> get updates => events
      .receiveBroadcastStream()
      .map((event) => Map<Object?, Object?>.from(event as Map));

  Future<T?> call<T>(String method, [Map<String, Object?>? args]) =>
      channel.invokeMethod<T>(method, args);
  Future<Map<Object?, Object?>> status() async =>
      Map<Object?, Object?>.from(await call<Map>('status') ?? {});
  Future<void> speak(String text) => call<void>('speak', {'text': text});
}
