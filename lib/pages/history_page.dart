import 'package:flutter/material.dart';

import '../bsu_data.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({
    super.key,
    this.places = const [],
    this.onOpenPlace,
  });

  // places the user opened recently (the dashboard fills this from _logHistory)
  final List<Place> places;

  // optional: open a place again when one of the history items is tapped
  final void Function(Place)? onOpenPlace;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
      ),
      body: Column(
        children: [
          Expanded(
            child: places.isEmpty
                ? const Center(
                    child: Text(
                      'No history yet. Open a building or tap the map and your visited places will show up here.',
                    ),
                  )
                : ListView.builder(
                    itemCount: places.length,
                    itemBuilder: (context, i) {
                      final p = places[i];
                      return ListTile(
                        leading: Icon(p.type.icon, color: p.statusColor),
                        title: Text(p.name),
                        subtitle: Text(p.statusLabel),
                        trailing: IconButton(
                          icon: const Icon(Icons.bookmark_border),
                          tooltip: 'Remove from history',
                          onPressed: () => Navigator.pop(context),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onOpenPlace?.call(p);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
