import 'package:flutter/material.dart';

import '../bsu_data.dart';
import '../widgets/place_photo.dart';

// the list of places that match what the user typed in the search bar.
// opens when the user presses search on the keyboard, or "See all results" under the
// suggestions on the map
class SearchResultsPage extends StatefulWidget {
  const SearchResultsPage({
    super.key,
    required this.query,
    this.onOpenPlace,
  });

  // what the user searched for
  final String query;

  // open a place on the map when one of the results is tapped
  final void Function(Place)? onOpenPlace;

  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );
  late String _query = widget.query.trim();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String v) {
    FocusScope.of(context).unfocus();
    setState(() => _query = v.trim());
  }

  // to connect (search): this searches the local list (kPlaces), same as the map search.
  // if there are too many places to load at once, replace searchPlaces() with a query
  // to the server
  List<SearchHit> get _hits => searchPlaces(_query, limit: kPlaces.length);

  @override
  Widget build(BuildContext context) {
    final hits = _hits;

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
                controller: _controller,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Search buildings, offices, rooms',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search',
                    onPressed: () => _search(_controller.text),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: _query.isEmpty
          ? const _Message('Type a building, office or room to search.')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              // +2: the "Searching for" heading on top and the footer at the bottom
              itemCount: hits.length + 2,
              itemBuilder: (context, i) {
                if (i == 0) return _Heading(_query);
                if (i == hits.length + 1) {
                  return hits.isEmpty
                      ? _Message('No places found for "$_query".')
                      : const _EndOfResults();
                }
                final hit = hits[i - 1];
                return _ResultCard(
                  hit: hit,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onOpenPlace?.call(hit.place);
                  },
                );
              },
            ),
    );
  }
}

// "Searching for..." and the text that was searched
class _Heading extends StatelessWidget {
  const _Heading(this.query);
  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Searching for...',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 2),
          Text(
            query,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// one result: photo on the left, name + description + rating on the right
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = hit.place;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlacePhoto(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(p.type.icon, size: 16, color: p.statusColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                  ),
                  // when the match was inside the building (a room, a feature)
                  if (hit.via.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Found: ${hit.via}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.lightBlue.shade800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        size: 16,
                        color: Color(0xFFFFB400),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        p.reviewCount == 0
                            ? 'No ratings yet'
                            : p.rating.toStringAsFixed(2),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// the "—— No More Results ——" line at the end of the list
class _EndOfResults extends StatelessWidget {
  const _EndOfResults();

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Divider(color: Colors.grey.shade600));
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'No More Results',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}
