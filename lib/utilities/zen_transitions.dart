import 'package:flutter/material.dart';

/// MaterialSharedAxis-Y page motion (350ms, fast-out-slow-in):
/// forward = covered page slides up and fades while the new page rises
/// in; pop reverses both. Player screen keeps its own slide-up.
PageRoute<void> sharedAxisYRoute(Widget page) => PageRouteBuilder(
  transitionDuration: const Duration(milliseconds: 350),
  reverseTransitionDuration: const Duration(milliseconds: 350),
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final inCurve =
    CurvedAnimation(parent: animation, curve: Curves.fastOutSlowIn);
    final outCurve = CurvedAnimation(
        parent: secondaryAnimation, curve: Curves.fastOutSlowIn);
    return FadeTransition(
      opacity: inCurve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
            .animate(inCurve),
        child: SlideTransition(
          position: Tween(begin: Offset.zero, end: const Offset(0, -0.25))
              .animate(outCurve),
          child: FadeTransition(
            opacity: ReverseAnimation(outCurve),
            child: child,
          ),
        ),
      ),
    );
  },
);

Future<void> pushSharedAxisY(BuildContext context, Widget page) =>
    Navigator.push(context, sharedAxisYRoute(page));