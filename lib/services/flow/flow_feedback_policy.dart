import 'package:get/get.dart';

import '../../models/flow/flow_models.dart';

class FlowFeedbackPolicy extends GetxService {
  double rewardFor(FlowFeedbackAction action) {
    switch (action) {
      case FlowFeedbackAction.like:
        return 1.5;
      case FlowFeedbackAction.moreLikeThis:
        return 1.0;
      case FlowFeedbackAction.completion:
        return .7;
      case FlowFeedbackAction.notNow:
        return -.25;
      case FlowFeedbackAction.playLessLikeThis:
        return -.6;
      case FlowFeedbackAction.earlySkip:
        return -1.0;
      case FlowFeedbackAction.blockTrack:
      case FlowFeedbackAction.blockArtist:
        return -2.0;
    }
  }

  bool increasesSkipStreak(FlowFeedbackAction action) {
    return action == FlowFeedbackAction.earlySkip ||
        action == FlowFeedbackAction.playLessLikeThis ||
        action == FlowFeedbackAction.notNow;
  }

  bool clearsSkipStreak(FlowFeedbackAction action) {
    return action == FlowFeedbackAction.like ||
        action == FlowFeedbackAction.moreLikeThis ||
        action == FlowFeedbackAction.completion;
  }
}
