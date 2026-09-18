const INBOX_SORT_OPTIONS = {
  newest: 'desc',
  oldest: 'asc',
};

const PRIORITY_WEIGHT = {
  urgent: 40,
  high: 30,
  medium: 20,
  low: 10,
};

const LABEL_BOOST = {
  'priorite-haute': 25,
  'pipeline-perdu': 15,
  'intent-prix': 5,
};

export const getNotificationRelevanceScore = notification => {
  const actor = notification.primary_actor || {};
  let score = 0;

  if (!notification.read_at) score += 1000;
  score += PRIORITY_WEIGHT[actor.priority] || 0;
  score += (actor.unread_count || 0) * 5;

  (actor.labels || []).forEach(label => {
    score += LABEL_BOOST[label] || 0;
  });

  score += (notification.last_activity_at || actor.last_activity_at || 0) / 1e6;

  return score;
};

const sortConfig = {
  newest: (a, b) =>
    getNotificationRelevanceScore(b) - getNotificationRelevanceScore(a),
  oldest: (a, b) =>
    (a.last_activity_at || a.created_at) - (b.last_activity_at || b.created_at),
};

export const sortComparator = (a, b, sortOrder) => {
  const sortDirection = INBOX_SORT_OPTIONS[sortOrder];
  if (sortOrder === 'newest' || sortOrder === 'oldest') {
    return sortConfig[sortOrder](a, b, sortDirection);
  }
  return 0;
};
