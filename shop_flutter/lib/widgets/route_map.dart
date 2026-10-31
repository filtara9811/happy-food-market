import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';

LatLng? ll(dynamic lat, dynamic lng) {
  final a = lat is num ? lat.toDouble() : double.tryParse('${lat ?? ''}');
  final b = lng is num ? lng.toDouble() : double.tryParse('${lng ?? ''}');
  if (a == null || b == null || (a == 0 && b == 0)) return null;
  return LatLng(a, b);
}

Widget _pin(IconData ic, Color c, {String? label}) => Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 3))]),
        child: Icon(ic, size: 17, color: Colors.white),
      ),
    ]);

/// Free OpenStreetMap map: me (rider) → shop → customer, with the route line.
class RouteMap extends StatelessWidget {
  final LatLng? me, shop, drop;
  final bool interactive;
  final double height;
  final VoidCallback? onTap;
  const RouteMap({super.key, this.me, this.shop, this.drop, this.interactive = false, this.height = 170, this.onTap});

  @override
  Widget build(BuildContext context) {
    final pts = [me, shop, drop].whereType<LatLng>().toList();
    if (pts.isEmpty) return const SizedBox.shrink();
    final opts = MapOptions(
      initialCenter: pts.first,
      initialZoom: 15,
      initialCameraFit: pts.length > 1 ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(44), maxZoom: 17) : null,
      interactionOptions: InteractionOptions(flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
      onTap: onTap == null ? null : (_, __) => onTap!(),
    );
    final map = FlutterMap(options: opts, children: [
      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.happyfood.shop', maxZoom: 19),
      if (pts.length > 1) PolylineLayer(polylines: [Polyline(points: pts, color: HF.goldDeep, strokeWidth: 4.5)]),
      MarkerLayer(markers: [
        if (shop != null) Marker(point: shop!, width: 40, height: 40, child: _pin(Icons.storefront_rounded, const Color(0xFF2563EB))),
        if (drop != null) Marker(point: drop!, width: 40, height: 40, child: _pin(Icons.home_rounded, const Color(0xFFDC2626))),
        if (me != null) Marker(point: me!, width: 40, height: 40, child: _pin(Icons.two_wheeler_rounded, const Color(0xFF16A34A))),
      ]),
      const SimpleAttributionWidget(source: Text('© OpenStreetMap', style: TextStyle(fontSize: 9))),
    ]);
    final body = ClipRRect(borderRadius: BorderRadius.circular(18), child: SizedBox(height: height, child: map));
    if (interactive || onTap == null) return body;
    return Stack(children: [
      body,
      Positioned(right: 8, bottom: 8, child: GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8)]), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.open_in_full_rounded, size: 14, color: HF.tx), const SizedBox(width: 4), Text('बड़ा नक्शा', style: HF.hi(11.5, w: FontWeight.w800))])))),
    ]);
  }
}

class RouteMapPage extends StatelessWidget {
  final LatLng? me, shop, drop;
  final String title;
  const RouteMapPage({super.key, this.me, this.shop, this.drop, this.title = 'रास्ता'});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title, style: HF.hi(17, w: FontWeight.w800)), backgroundColor: HF.card, foregroundColor: HF.tx, elevation: 0),
        body: Column(children: [
          Expanded(child: RouteMap(me: me, shop: shop, drop: drop, interactive: true, height: double.infinity)),
          Container(
            color: HF.card, padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Wrap(spacing: 16, runSpacing: 6, children: [
              if (me != null) _leg(Icons.two_wheeler_rounded, const Color(0xFF16A34A), 'आप'),
              if (shop != null) _leg(Icons.storefront_rounded, const Color(0xFF2563EB), 'दुकान (पिकअप)'),
              if (drop != null) _leg(Icons.home_rounded, const Color(0xFFDC2626), 'ग्राहक (डिलीवरी)'),
            ]),
          ),
        ]),
      );
  Widget _leg(IconData i, Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, color: c, size: 18), const SizedBox(width: 4), Text(t, style: HF.hi(12.5, w: FontWeight.w700))]);
}
