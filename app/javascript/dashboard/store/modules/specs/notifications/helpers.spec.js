import {
  sortComparator,
  getNotificationRelevanceScore,
} from '../../notifications/helpers';

const notifications = [
  {
    id: 1,
    read_at: '2024-02-07T11:42:39.988Z',
    created_at: 1707328400,
    last_activity_at: 1707328400,
    primary_actor: { priority: 'low', unread_count: 0, labels: [] },
  },
  {
    id: 2,
    read_at: null,
    created_at: 1707233688,
    last_activity_at: 1707233688,
    primary_actor: { priority: 'urgent', unread_count: 3, labels: ['priorite-haute'] },
  },
  {
    id: 3,
    read_at: null,
    created_at: 1707233672,
    last_activity_at: 1707233672,
    primary_actor: { priority: 'medium', unread_count: 1, labels: [] },
  },
];

describe('#sortComparator', () => {
  it('returns notifications sorted by relevance for newest', () => {
    const sortedNotifications = [...notifications].sort((a, b) =>
      sortComparator(a, b, 'newest')
    );

    expect(sortedNotifications[0].id).toBe(2);
    expect(getNotificationRelevanceScore(sortedNotifications[0])).toBeGreaterThan(
      getNotificationRelevanceScore(sortedNotifications[1])
    );
  });

  it('returns the notifications sorted by oldest activity', () => {
    const sortedNotifications = [...notifications].sort((a, b) =>
      sortComparator(a, b, 'oldest')
    );

    expect(sortedNotifications.map(n => n.id)).toEqual([3, 2, 1]);
  });
});
