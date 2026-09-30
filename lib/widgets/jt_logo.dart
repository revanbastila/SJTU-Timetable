import 'package:flutter/material.dart';

class JtLogo extends StatelessWidget {
  const JtLogo({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: const Color(0xFF123B6D),
          borderRadius: BorderRadius.circular(size * .28)),
      child: Stack(alignment: Alignment.center, children: [
        Text('交',
            style: TextStyle(
                color: Colors.white,
                fontSize: size * .56,
                height: 1,
                fontWeight: FontWeight.w800)),
        Positioned(
            left: size * .14,
            right: size * .14,
            bottom: size * .12,
            child: Container(height: 2, color: const Color(0xFF75B7EE))),
      ]),
    );
  }
}
