const classGap = Duration(hours: 2);
const maxJudgedPerClass = 6;
const maxUserMessagesPerClass = 12;

/// lastMessageAt 为空，或距 now 已满 2 小时，就该新开一节。不按日历日切。
bool gapStartsNewClass(DateTime? lastMessageAt, DateTime now) {
  if (lastMessageAt == null) return true;
  return now.difference(lastMessageAt) >= classGap;
}

/// judged >= 6 或 userMessages >= 12。
bool classIsFull({required int judged, required int userMessages}) {
  return judged >= maxJudgedPerClass || userMessages >= maxUserMessagesPerClass;
}
