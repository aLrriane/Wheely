import 'package:flutter/material.dart';

import '../bsu_data.dart';
import '../widgets/place_photo.dart';
import '../widgets/rating_stars.dart';

// the places the user saved (bookmarked)
class SavesPage extends StatefulWidget {
  const SavesPage({
    super.key,
    this.places = const [],
    this.onOpenPlace,
    this.onRemove,
  });

  // the saved places to show
  final List<Place> places;

  // optional: open a place on the map when one of the items is tapped
  final void Function(Place)? onOpenPlace;

  // optional: tells the map screen that a place was removed from saved, so its
  // bookmark is turned off there too
  final void Function(Place)? onRemove;

  @override
  State<SavesPage> createState() => _SavesPageState();
}

class _SavesPageState extends State<SavesPage> {
  // how many places show before "View all" is tapped
  static const _previewCount = 4;

  late final List<Place> _places = List<Place>.of(widget.places);
  final _searchController = TextEditingController();
  String _query = '';
  bool _viewAll = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // to connect: also remove the place from the user's saved list in the database here
  // (the map screen does it through onRemove, see _persistSave in dashboard_page.dart)
  void _remove(Place p) {
    final index = _places.indexOf(p);
    setState(() => _places.remove(p));
    widget.onRemove?.call(p);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${p.name} from saved'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              // saving it again goes through the same callback as removing it
              setState(() => _places.insert(index.clamp(0, _places.length), p));
              widget.onRemove?.call(p);
            },
          ),
        ),
      );
  }

  // the saved places that match the search box (name, code, or type)
  List<Place> get _matching {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _places;
    return _places.where((p) => p.matchedOn(q) != null).toList();
  }

  @override
  Widget build(BuildContext context) {
    final matching = _matching;
    final searching = _query.trim().isNotEmpty;
    // "View all" only matters when the list is longer than the preview
    final canExpand = !searching && matching.length > _previewCount;
    final shown = (canExpand && !_viewAll)
        ? matching.take(_previewCount).toList()
        : matching;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(30),
            color: Colors.white,
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search saved places',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  suffixIcon: _query.isEmpty
                      ? const Icon(Icons.search)
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Places',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (canExpand)
                  TextButton(
                    onPressed: () => setState(() => _viewAll = !_viewAll),
                    child: Text(_viewAll ? 'Show less' : 'View all'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        searching
                            ? 'No saved places match "${_query.trim()}".'
                            : 'No saved places yet. Tap Save on a place and it will show up here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final p = shown[i];
                      return _SavedCard(
                        place: p,
                        onDelete: () => _remove(p),
                        onTap: widget.onOpenPlace == null
                            ? null
                            : () {
                                Navigator.pop(context);
                                widget.onOpenPlace!(p);
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

// one saved place: photo, type icon + name, stars, and the red delete button
class _SavedCard extends StatelessWidget {
  const _SavedCard({required this.place, required this.onDelete, this.onTap});

  final Place place;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlacePhoto(width: 130, height: 100),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(place.type.icon, size: 18, color: place.statusColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            place.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (place.reviewCount == 0)
                      Text(
                        'No ratings yet',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      )
                    else
                      RatingStars(place.rating),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: kInaccessible),
              tooltip: 'Delete ${place.name} from saved',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
