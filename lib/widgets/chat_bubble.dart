import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final bool isMe;
  final String? pilotName;
  final String text;
  final Widget user;
  final int? timestamp;

  const ChatBubble(
      this.isMe, this.text, this.user, this.pilotName, this.timestamp,
      {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Column(
        children: [
          Row(
              mainAxisAlignment:
                  isMe ? MainAxisAlignment.start : MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              // mainAxisSize: MainAxisSize.min,
              mainAxisSize: MainAxisSize.max,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8),
                  child: Card(
                    color: isMe
                        ? Colors.blue
                        : const Color.fromARGB(255, 230, 230, 230),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(10),
                            bottomLeft: isMe
                                ? const Radius.circular(1)
                                : const Radius.circular(10),
                            topRight: const Radius.circular(10),
                            bottomRight: isMe
                                ? const Radius.circular(10)
                                : const Radius.circular(1))),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        text,
                        maxLines: 15,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                        style:
                            const TextStyle(fontSize: 18, color: Colors.black),
                      ),
                    ),
                  ),
                ),

                // --- Sender avatar image
                if (!isMe) user,
              ]),
          Padding(
            padding: const EdgeInsets.only(left: 50, right: 50),
            child: Row(
              mainAxisAlignment:
                  isMe ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                if (pilotName != null)
                  Text(
                    pilotName!,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                if (pilotName != null && timestamp != null)
                  const SizedBox(
                    width: 20,
                  ),
                if (timestamp != null)
                  Text(
                    "${Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - timestamp!).inMinutes}m",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  )
              ],
            ),
          )
        ],
      ),
    );
  }
}
