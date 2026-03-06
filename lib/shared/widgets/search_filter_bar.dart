import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/haptic_service.dart';

class SearchFilterBar extends StatefulWidget {
  final ValueChanged<String> onSearchChanged;
  final List<String>? filters;
  final String? activeFilter;
  final ValueChanged<String?>? onFilterChanged;
  final String hintText;

  const SearchFilterBar({
    super.key,
    required this.onSearchChanged,
    this.filters,
    this.activeFilter,
    this.onFilterChanged,
    this.hintText = 'Search...',
  });

  @override
  State<SearchFilterBar> createState() => _SearchFilterBarState();
}

class _SearchFilterBarState extends State<SearchFilterBar> {
  bool _isExpanded = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppColors.space24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: AnimatedCrossFade(
                  duration: const Duration(milliseconds: 250),
                  crossFadeState: _isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(height: 44),
                  secondChild: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: _controller,
                      onChanged: widget.onSearchChanged,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        prefixIcon:
                            const Icon(Iconsax.search_normal, size: 18),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppColors.space16,
                          vertical: AppColors.space12,
                        ),
                        suffixIcon: _controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _controller.clear();
                                  widget.onSearchChanged('');
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppColors.space8),
              GestureDetector(
                onTap: () {
                  HapticService.lightClick();
                  setState(() => _isExpanded = !_isExpanded);
                  if (!_isExpanded) {
                    _controller.clear();
                    widget.onSearchChanged('');
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _isExpanded
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.surfaceLight,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusSmall),
                    border: Border.all(
                      color: _isExpanded
                          ? AppColors.primary.withValues(alpha: 0.3)
                          : AppColors.borderLight,
                    ),
                  ),
                  child: Icon(
                    _isExpanded ? Icons.close : Iconsax.search_normal,
                    size: 18,
                    color:
                        _isExpanded ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          if (widget.filters != null && widget.filters!.isNotEmpty) ...[
            const SizedBox(height: AppColors.space8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.filters!.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppColors.space8),
                itemBuilder: (context, index) {
                  final filter = widget.filters![index];
                  final isActive = filter == widget.activeFilter;
                  return ChoiceChip(
                    label: Text(filter),
                    selected: isActive,
                    onSelected: (_) {
                      HapticService.selection();
                      widget.onFilterChanged
                          ?.call(isActive ? null : filter);
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
