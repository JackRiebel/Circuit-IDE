import 'package:flutter/animation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/painting.dart';

/// Cisco Momentum-inspired spacing scale (4px base unit)
class Spacing {
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double xxxxl = 48;
}

class Radii {
  static const double xs = 3;
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 10;
  static const double pill = 1000;
}

/// Enterprise type scale — compact but readable
class FontSizes {
  static const double xxs = 10;
  static const double xs = 11;
  static const double sm = 12;
  static const double md = 13;
  static const double base = 14;
  static const double lg = 15;
  static const double xl = 17;
  static const double xxl = 20;
  static const double title = 24;
  static const double display = 32;
}

/// The approved icon vocabulary for Studio surfaces.
///
/// Keeping these symbols here makes visual review and future platform-specific
/// substitutions tractable instead of scattering Material choices through
/// every task, drawer, and composer widget.
abstract final class StudioIcons {
  static const IconData accountTreeOutlined = Icons.account_tree_outlined;
  static const IconData add = Icons.add;
  static const IconData addCircleOutline = Icons.add_circle_outline;
  static const IconData addCommentOutlined = Icons.add_comment_outlined;
  static const IconData addToQueueOutlined = Icons.add_to_queue_outlined;
  static const IconData altRouteOutlined = Icons.alt_route_outlined;
  static const IconData arrowBack = Icons.arrow_back;
  static const IconData arrowForward = Icons.arrow_forward;
  static const IconData arrowOutward = Icons.arrow_outward;
  static const IconData arrowUpward = Icons.arrow_upward;
  static const IconData articleOutlined = Icons.article_outlined;
  static const IconData autoAwesomeOutlined = Icons.auto_awesome_outlined;
  static const IconData backHandOutlined = Icons.back_hand_outlined;
  static const IconData block = Icons.block;
  static const IconData brokenImageOutlined = Icons.broken_image_outlined;
  static const IconData buildOutlined = Icons.build_outlined;
  static const IconData callMergeOutlined = Icons.call_merge_outlined;
  static const IconData cancelOutlined = Icons.cancel_outlined;
  static const IconData chatBubbleOutline = Icons.chat_bubble_outline;
  static const IconData check = Icons.check;
  static const IconData checkCircle = Icons.check_circle;
  static const IconData checkBox = Icons.check_box;
  static const IconData checkBoxOutlineBlank = Icons.check_box_outline_blank;
  static const IconData checkCircleOutline = Icons.check_circle_outline;
  static const IconData chevronLeft = Icons.chevron_left;
  static const IconData chevronRight = Icons.chevron_right;
  static const IconData close = Icons.close;
  static const IconData closeFullscreen = Icons.close_fullscreen;
  static const IconData code = Icons.code;
  static const IconData compareOutlined = Icons.compare_outlined;
  static const IconData computerOutlined = Icons.computer_outlined;
  static const IconData contentCopyOutlined = Icons.content_copy_outlined;
  static const IconData copy = Icons.copy;
  static const IconData copyOutlined = Icons.copy_outlined;
  static const IconData createNewFolderOutlined =
      Icons.create_new_folder_outlined;
  static const IconData dataObjectOutlined = Icons.data_object_outlined;
  static const IconData dataUsageOutlined = Icons.data_usage_outlined;
  static const IconData datasetLinkedOutlined = Icons.dataset_linked_outlined;
  static const IconData deleteOutline = Icons.delete_outline;
  static const IconData descriptionOutlined = Icons.description_outlined;
  static const IconData difference = Icons.difference;
  static const IconData differenceOutlined = Icons.difference_outlined;
  static const IconData editNote = Icons.edit_note;
  static const IconData editOutlined = Icons.edit_outlined;
  static const IconData editSquare = Icons.edit_square;
  static const IconData errorOutline = Icons.error_outline;
  static const IconData eventAvailableOutlined = Icons.event_available_outlined;
  static const IconData expandMore = Icons.expand_more;
  static const IconData factCheckOutlined = Icons.fact_check_outlined;
  static const IconData fileDownloadOutlined = Icons.file_download_outlined;
  static const IconData filePresentOutlined = Icons.file_present_outlined;
  static const IconData filterList = Icons.filter_list;
  static const IconData folderCopyOutlined = Icons.folder_copy_outlined;
  static const IconData folderOpenOutlined = Icons.folder_open_outlined;
  static const IconData folderOutlined = Icons.folder_outlined;
  static const IconData folderSpecialOutlined = Icons.folder_special_outlined;
  static const IconData folderZipOutlined = Icons.folder_zip_outlined;
  static const IconData formatListBulleted = Icons.format_list_bulleted;
  static const IconData forumOutlined = Icons.forum_outlined;
  static const IconData history = Icons.history;
  static const IconData historyToggleOffOutlined =
      Icons.history_toggle_off_outlined;
  static const IconData imageOutlined = Icons.image_outlined;
  static const IconData infoOutline = Icons.info_outline;
  static const IconData insertChartOutlined = Icons.insert_chart_outlined;
  static const IconData insertDriveFileOutlined =
      Icons.insert_drive_file_outlined;
  static const IconData inventory2Outlined = Icons.inventory_2_outlined;
  static const IconData iosShareOutlined = Icons.ios_share_outlined;
  static const IconData keyboardArrowDown = Icons.keyboard_arrow_down;
  static const IconData keyboardArrowUp = Icons.keyboard_arrow_up;
  static const IconData language = Icons.language;
  static const IconData memoryOutlined = Icons.memory_outlined;
  static const IconData moreHoriz = Icons.more_horiz;
  static const IconData noteAddOutlined = Icons.note_add_outlined;
  static const IconData openInFullOutlined = Icons.open_in_full_outlined;
  static const IconData openInNew = Icons.open_in_new;
  static const IconData pictureAsPdfOutlined = Icons.picture_as_pdf_outlined;
  static const IconData pushPin = Icons.push_pin;
  static const IconData queryStatsOutlined = Icons.query_stats_outlined;
  static const IconData radioButtonChecked = Icons.radio_button_checked;
  static const IconData rateReviewOutlined = Icons.rate_review_outlined;
  static const IconData refresh = Icons.refresh;
  static const IconData removeCircleOutline = Icons.remove_circle_outline;
  static const IconData replayOutlined = Icons.replay_outlined;
  static const IconData restore = Icons.restore;
  static const IconData restorePageOutlined = Icons.restore_page_outlined;
  static const IconData routeOutlined = Icons.route_outlined;
  static const IconData scheduleOutlined = Icons.schedule_outlined;
  static const IconData screenshotMonitorOutlined =
      Icons.screenshot_monitor_outlined;
  static const IconData search = Icons.search;
  static const IconData securityOutlined = Icons.security_outlined;
  static const IconData settingsOutlined = Icons.settings_outlined;
  static const IconData shieldOutlined = Icons.shield_outlined;
  static const IconData skipNext = Icons.skip_next;
  static const IconData slideshowOutlined = Icons.slideshow_outlined;
  static const IconData smartToyOutlined = Icons.smart_toy_outlined;
  static const IconData stopCircleOutlined = Icons.stop_circle_outlined;
  static const IconData straightenOutlined = Icons.straighten_outlined;
  static const IconData tableChartOutlined = Icons.table_chart_outlined;
  static const IconData taskAltOutlined = Icons.task_alt_outlined;
  static const IconData terminalOutlined = Icons.terminal_outlined;
  static const IconData thumbDownAltOutlined = Icons.thumb_down_alt_outlined;
  static const IconData thumbUpAltOutlined = Icons.thumb_up_alt_outlined;
  static const IconData travelExplore = Icons.travel_explore;
  static const IconData tuneOutlined = Icons.tune_outlined;
  static const IconData unarchiveOutlined = Icons.unarchive_outlined;
  static const IconData unfoldLess = Icons.unfold_less;
  static const IconData unfoldMore = Icons.unfold_more;
  static const IconData verifiedOutlined = Icons.verified_outlined;
  static const IconData viewCarouselOutlined = Icons.view_carousel_outlined;
  static const IconData viewSidebarOutlined = Icons.view_sidebar_outlined;
  static const IconData warningAmberRounded = Icons.warning_amber_rounded;
}

enum UiDensityMode { comfortable, compact }

class EditorDefaults {
  static const double fontSize = 14;
  static const double lineHeight = 1.5;
  static const String fontFamily = 'JetBrains Mono';
  static const String studioMonospaceFontFamily = 'SF Mono';
  static const String fallbackFontFamily = 'Menlo';
}

class AnimationDurations {
  static const Duration instant = Duration(milliseconds: 50);
  static const Duration fast = Duration(milliseconds: 100);
  static const Duration normal = Duration(milliseconds: 150);
  static const Duration smooth = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
  static const Duration panel = Duration(milliseconds: 250);
}

class AnimationCurves {
  static const Curve snappy = Cubic(0.2, 0.8, 0.2, 1.0);
  static const Curve smooth = Cubic(0.4, 0.0, 0.2, 1.0);
}

class LayoutDimensions {
  static const double activityBarWidth = 48;
  static const double sidePanelMinWidth = 200;
  static const double sidePanelDefaultWidth = 260;
  static const double sidePanelMaxWidth = 500;
  static const double statusBarHeight = 28;
  static const double tabBarHeight = 36;
  static const double breadcrumbHeight = 24;
  static const double chatInputMinHeight = 80;
  static const double chatPanelMinWidth = 300;
  static const double chatPanelDefaultWidth = 380;
  static const double terminalMinHeight = 100;
  static const double terminalDefaultHeight = 200;
  static const double terminalMaxHeight = 400;
  static const double chatPanelMaxWidth = 500;
  static const double titleBarHeight = 38;
}

class Shadows {
  static const List<BoxShadow> subtle = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> medium = [
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
  ];

  static List<BoxShadow> glow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.25),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: color.withValues(alpha: 0.08),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> softGlow(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 8),
  ];
}
