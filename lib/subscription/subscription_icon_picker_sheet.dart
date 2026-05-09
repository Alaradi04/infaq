import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/profile/subscription_icon_storage.dart';
import 'package:infaq/subscription/subscription_preset_icons.dart';
import 'package:infaq/ui/infaq_service_form_widgets.dart';

/// Fixed logical size for preset logos in the picker grid (dp).
const double _kPresetIconSize = 48;

/// Cell width/height ratio — tuned so label + fixed icon fit without huge tiles.
const double _kPresetGridAspectRatio = 0.88;

/// Reserved height for labels (2 lines) so every tile lines up the same icon row.
const double _kPresetLabelBlockHeight = 30;

/// Bottom sheet: searchable grid of preset icons; optional in-sheet gallery row.
Future<void> showSubscriptionIconPickerSheet({
  required BuildContext context,
  required void Function(String iconKey) onPresetChosen,
  VoidCallback? onChooseGallery,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return _SubscriptionIconPickerBody(
            scrollController: scrollController,
            onPresetChosen: (key) {
              Navigator.pop(ctx);
              onPresetChosen(key);
            },
            onChooseGallery: onChooseGallery == null
                ? null
                : () {
                    Navigator.pop(ctx);
                    onChooseGallery();
                  },
          );
        },
      );
    },
  );
}

class _SubscriptionIconPickerBody extends StatefulWidget {
  const _SubscriptionIconPickerBody({
    required this.scrollController,
    required this.onPresetChosen,
    required this.onChooseGallery,
  });

  final ScrollController scrollController;
  final void Function(String iconKey) onPresetChosen;
  final VoidCallback? onChooseGallery;

  @override
  State<_SubscriptionIconPickerBody> createState() =>
      _SubscriptionIconPickerBodyState();
}

class _SubscriptionIconPickerBodyState extends State<_SubscriptionIconPickerBody> {
  final _filterCtrl = TextEditingController();

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filterCtrl.text.isEmpty
        ? kSubscriptionPresetIcons
        : kSubscriptionPresetIcons
              .where(
                (p) =>
                    p.label.toLowerCase().contains(
                      _filterCtrl.text.toLowerCase().trim(),
                    ) ||
                    p.key.contains(_filterCtrl.text.toLowerCase().trim()),
              )
              .toList();

    return Material(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Subscription icon',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _filterCtrl,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search Netflix, Spotify…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: isDark
                    ? cs.surfaceContainerHigh
                    : const Color(0xFFF0F2F0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          if (widget.onChooseGallery != null) ...[
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: kServiceFormGreen,
              ),
              title: const Text('Upload from gallery'),
              subtitle: const Text('Use your own image'),
              onTap: widget.onChooseGallery,
            ),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(
              'Popular services',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.65),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No matches',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : GridView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: _kPresetGridAspectRatio,
                        ),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final p = filtered[i];
                      return _PresetCell(
                        preset: p,
                        onTap: () => widget.onPresetChosen(p.key),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PresetCell extends StatelessWidget {
  const _PresetCell({required this.preset, required this.onTap});

  final SubscriptionPresetIcon preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = InfaqSubscriptionIconStorage.presetPublicUrl(
      Supabase.instance.client,
      preset.key,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Align(
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: _kPresetIconSize,
                height: _kPresetIconSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDark
                        ? cs.surfaceContainerHighest
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: kServiceFormGreen.withValues(alpha: 0.2),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: url != null && url.isNotEmpty
                        ? Image.network(
                            url,
                            width: _kPresetIconSize,
                            height: _kPresetIconSize,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.image_not_supported_outlined,
                              size: 20,
                              color: cs.primary.withValues(alpha: 0.35),
                            ),
                          )
                        : Icon(
                            Icons.apps_rounded,
                            size: 22,
                            color: cs.primary.withValues(alpha: 0.45),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: _kPresetLabelBlockHeight,
                width: double.infinity,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    preset.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.75),
                      height: 1.12,
                    ),
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
