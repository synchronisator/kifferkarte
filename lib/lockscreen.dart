import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kifferkarte/main.dart';
import 'package:kifferkarte/provider_manager.dart';
import 'package:slide_to_act/slide_to_act.dart';

class Lockscreen extends ConsumerStatefulWidget {
  Lockscreen({super.key});

  @override
  ConsumerState<Lockscreen> createState() => _LockscreenState();
}

class _LockscreenState extends ConsumerState<Lockscreen> {
  @override
  Widget build(BuildContext context) {
    bool inWay = ref.watch(inWayProvider);
    bool inCircle = ref.watch(inCircleProvider);
    bool updating = ref.watch(updatingProvider);
    bool smokeable = false;
    String text = "";
    DateTime now = DateTime.now();
    if ((!inCircle && !inWay) ||
        (!inCircle && (now.hour < 7 || now.hour >= 20))) {
      smokeable = true;
    }
    text = smokeable ? "Kiffen vermutlich erlaubt" : "Kiffen nicht erlaubt";
    return Scaffold(
      body: Expanded(
        child: Container(
          color: Colors.black,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Center(
                  child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  text,
                  style: TextStyle(fontSize: 50, color: Colors.white),
                ),
              )),
              Center(
                  child: Icon(
                smokeable ? Icons.smoking_rooms : Icons.smoke_free,
                color: Colors.white,
                size: 200,
              )),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SlideAction(
                    text: "Schlittern um zu entschlüsseln",
                    onSubmit: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
