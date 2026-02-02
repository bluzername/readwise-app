import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Design tokens for the Discover card
class DiscoverCardTokens {
  // Layout
  static const double cardRadius = 14.0;
  static const double imageAspectRatio = 0.56; // ~16:9
  static const double horizontalPadding = 14.0;
  static const double verticalSpacing = 10.0;
  static const double bulletSpacing = 6.0;

  // Typography
  static const double sourceFontSize = 13.0;
  static const double timeFontSize = 13.0;
  static const double bulletFontSize = 15.0;
  static const double bulletLineHeight = 1.4;

  // Colors - Light mode
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE5E7EB);
  static const Color lightTextPrimary = Color(0xFF1A1A1A);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightTextTertiary = Color(0xFF9CA3AF);
  static const Color lightImagePlaceholder = Color(0xFFF3F4F6);

  // Colors - Dark mode
  static const Color darkBackground = Color(0xFF1C1C1E);
  static const Color darkBorder = Color(0xFF2C2C2E);
  static const Color darkTextPrimary = Color(0xFFF5F5F5);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);
  static const Color darkTextTertiary = Color(0xFF6B7280);
  static const Color darkImagePlaceholder = Color(0xFF2C2C2E);
}

/// Data model for the Discover card
class DiscoverCardModel {
  final String? imageUrl;
  final List<String> bullets;
  final String sourceLabel;
  final String relativeTime;
  final VoidCallback? onTap;
  final VoidCallback? onTapSource;

  const DiscoverCardModel({
    this.imageUrl,
    required this.bullets,
    required this.sourceLabel,
    required this.relativeTime,
    this.onTap,
    this.onTapSource,
  });
}

/// Discover-style card widget
///
/// A visually rich card with:
/// - Edge-to-edge image at top
/// - Metadata row (source + timestamp)
/// - Bullet point summary (3-5 points)
class DiscoverCard extends StatefulWidget {
  final DiscoverCardModel model;

  const DiscoverCard({super.key, required this.model});

  @override
  State<DiscoverCard> createState() => _DiscoverCardState();
}

class _DiscoverCardState extends State<DiscoverCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tokens = DiscoverCardTokens();

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        HapticFeedback.lightImpact();
        widget.model.onTap?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedOpacity(
          opacity: _isPressed ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? DiscoverCardTokens.darkBackground
                  : DiscoverCardTokens.lightBackground,
              borderRadius: BorderRadius.circular(DiscoverCardTokens.cardRadius),
              border: Border.all(
                color: isDark
                    ? DiscoverCardTokens.darkBorder
                    : DiscoverCardTokens.lightBorder,
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top image
                _buildImage(isDark),

                // Content section
                Padding(
                  padding: const EdgeInsets.all(DiscoverCardTokens.horizontalPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Metadata row
                      _buildMetadataRow(isDark),

                      const SizedBox(height: DiscoverCardTokens.verticalSpacing),

                      // Bullet summary
                      _buildBulletList(isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(bool isDark) {
    if (widget.model.imageUrl == null || widget.model.imageUrl!.isEmpty) {
      // Placeholder when no image
      return AspectRatio(
        aspectRatio: 1 / DiscoverCardTokens.imageAspectRatio,
        child: Container(
          color: isDark
              ? DiscoverCardTokens.darkImagePlaceholder
              : DiscoverCardTokens.lightImagePlaceholder,
          child: Center(
            child: Icon(
              Icons.article_outlined,
              size: 32,
              color: isDark
                  ? DiscoverCardTokens.darkTextTertiary
                  : DiscoverCardTokens.lightTextTertiary,
            ),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1 / DiscoverCardTokens.imageAspectRatio,
      child: CachedNetworkImage(
        imageUrl: widget.model.imageUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: isDark
              ? DiscoverCardTokens.darkImagePlaceholder
              : DiscoverCardTokens.lightImagePlaceholder,
        ),
        errorWidget: (context, url, error) => Container(
          color: isDark
              ? DiscoverCardTokens.darkImagePlaceholder
              : DiscoverCardTokens.lightImagePlaceholder,
          child: Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              size: 32,
              color: isDark
                  ? DiscoverCardTokens.darkTextTertiary
                  : DiscoverCardTokens.lightTextTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataRow(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Source label (tappable)
        Flexible(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.model.onTapSource?.call();
            },
            child: Text(
              widget.model.sourceLabel,
              style: TextStyle(
                fontSize: DiscoverCardTokens.sourceFontSize,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? DiscoverCardTokens.darkTextSecondary
                    : DiscoverCardTokens.lightTextSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Timestamp
        Text(
          widget.model.relativeTime,
          style: TextStyle(
            fontSize: DiscoverCardTokens.timeFontSize,
            fontWeight: FontWeight.w400,
            color: isDark
                ? DiscoverCardTokens.darkTextTertiary
                : DiscoverCardTokens.lightTextTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildBulletList(bool isDark) {
    // Limit to 5 bullets max, show at least what we have
    final bullets = widget.model.bullets.take(5).toList();

    if (bullets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: bullets.map((bullet) => Padding(
        padding: const EdgeInsets.only(bottom: DiscoverCardTokens.bulletSpacing),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bullet marker - simple dash
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 4,
                height: 1.5,
                color: isDark
                    ? DiscoverCardTokens.darkTextTertiary
                    : DiscoverCardTokens.lightTextTertiary,
              ),
            ),
            const SizedBox(width: 8),
            // Bullet text - no line limit, let it expand
            Expanded(
              child: Text(
                bullet,
                style: TextStyle(
                  fontSize: DiscoverCardTokens.bulletFontSize,
                  fontWeight: FontWeight.w400,
                  height: DiscoverCardTokens.bulletLineHeight,
                  color: isDark
                      ? DiscoverCardTokens.darkTextPrimary
                      : DiscoverCardTokens.lightTextPrimary,
                ),
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }
}

/// Compact variant of the Discover card (smaller image, fewer bullets)
class DiscoverCardCompact extends StatelessWidget {
  final DiscoverCardModel model;

  const DiscoverCardCompact({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    // Create a modified model with max 2 bullets
    final compactModel = DiscoverCardModel(
      imageUrl: model.imageUrl,
      bullets: model.bullets.take(2).toList(),
      sourceLabel: model.sourceLabel,
      relativeTime: model.relativeTime,
      onTap: model.onTap,
      onTapSource: model.onTapSource,
    );

    return DiscoverCard(model: compactModel);
  }
}

/// Helper to format relative time
String formatRelativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inMinutes < 1) {
    return 'now';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m ago';
  } else if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  } else if (difference.inDays == 1) {
    return 'Yesterday';
  } else if (difference.inDays < 7) {
    return '${difference.inDays}d ago';
  } else {
    // Return short weekday for older items
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[dateTime.weekday - 1];
  }
}
