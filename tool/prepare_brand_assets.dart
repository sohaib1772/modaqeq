import 'dart:io';
import 'package:image/image.dart' as image;

// Platform launch screens need density-correct sizes and Android 12 safe zones.
void main() {
  final logo = image.decodePng(File('assets/logo.png').readAsBytesSync())!;
  final splash = image.copyResize(
    logo,
    width: 720,
    height: 720,
    interpolation: image.Interpolation.cubic,
  );
  File('assets/splash.png').writeAsBytesSync(image.encodePng(splash));
  final android12 = image.Image(width: 1152, height: 1152, numChannels: 4);
  image.compositeImage(android12, splash, dstX: 216, dstY: 216);
  File(
    'assets/splash_android12.png',
  ).writeAsBytesSync(image.encodePng(android12));
}
