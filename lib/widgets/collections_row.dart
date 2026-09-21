import 'package:flutter/material.dart';

import '../models/collection.dart';
import 'collection_card.dart';
import 'section_header.dart';

class CollectionsRow extends StatelessWidget {
  const CollectionsRow({
    super.key,
    required this.title,
    required this.collections,
    required this.onOpen,
  });

  final String title;
  final List<Collection> collections;
  final void Function(Collection collection) onOpen;

  @override
  Widget build(BuildContext context) {
    if (collections.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, icon: Icons.album_rounded),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: collections.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) =>
                CollectionCard(collection: collections[i], onTap: () => onOpen(collections[i])),
          ),
        ),
      ],
    );
  }
}