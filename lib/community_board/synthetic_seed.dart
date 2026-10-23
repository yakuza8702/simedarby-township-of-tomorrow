/// SYNTHETIC DATA generated for this prototype — NOT real resident data. Used
/// because no proprietary datasets are provided (challenge data-integrity rule).
///
/// The seed below is plain JSON (ISO-8601 timestamps), so it is `const` and is
/// decoded by `CommunityBoardStore.load()` through `BoardPost.fromJson` — the
/// same path a persisted `community_board.json` takes. Nothing here is a real
/// name, email, phone number or address: authors are invented "Resident X-nn"
/// labels, locations are precinct-level only, and every entry carries
/// `isSynthetic: true` so the UI can label it.
///
/// Coverage contract (pinned by `test/community_board_test.dart`):
///   * 8 posts (≥8), 16 comments in total (≥15);
///   * both precincts ("Precinct A", "Precinct B");
///   * all 5 `kBoardCategories` values.
library;

const List<Map<String, dynamic>> kSyntheticBoardSeed = [
  {
    'id': 'seed-post-01',
    'title': 'Deep pothole at the main crossing needs a look',
    'body': 'There is a pothole roughly the size of a dinner plate on the '
        'crossing approach. Two drivers swerved around it this morning and a '
        'cyclist nearly lost their front wheel. Could it be marked or filled '
        'before the wet season?',
    'category': 'Safety',
    'precinct': 'Precinct A',
    'authorLabel': 'Resident A-12',
    'createdAt': '2026-09-24T08:15:00.000',
    'upvotes': 27,
    'comments': [
      {
        'id': 'seed-cmt-01-1',
        'authorLabel': 'Resident A-04',
        'body': 'Confirmed — I reported the same spot a fortnight ago. Worth '
            'putting a cone there in the meantime.',
        'isSynthetic': true,
        'createdAt': '2026-09-24T09:02:00.000',
      },
      {
        'id': 'seed-cmt-01-2',
        'authorLabel': 'Resident B-07',
        'body': 'Seen it from the other side too. It is deeper after the rain.',
        'isSynthetic': true,
        'createdAt': '2026-09-24T18:40:00.000',
      },
      {
        'id': 'seed-cmt-01-3',
        'authorLabel': 'Resident A-21',
        'body': 'Adding my upvote. School run uses that crossing every day.',
        'isSynthetic': true,
        'createdAt': '2026-09-25T07:05:00.000',
      },
    ],
    'isSynthetic': true,
  },
  {
    'id': 'seed-post-02',
    'title': 'Playground swing set — one bay out of action',
    'body': 'The left-hand swing bay has a frayed chain and the seat is taped '
        'up. The other bay is fine, which means a queue of small children at '
        'peak times. A repair or a "closed" tag would both help.',
    'category': 'Facilities',
    'precinct': 'Precinct B',
    'authorLabel': 'Resident B-07',
    'createdAt': '2026-09-26T16:30:00.000',
    'upvotes': 19,
    'comments': [
      {
        'id': 'seed-cmt-02-1',
        'authorLabel': 'Resident B-15',
        'body': 'Passing by tomorrow morning, I can photograph the chain for '
            'the maintenance request.',
        'isSynthetic': true,
        'createdAt': '2026-09-26T19:12:00.000',
      },
      {
        'id': 'seed-cmt-02-2',
        'authorLabel': 'Resident A-09',
        'body': 'We usually visit on weekends — would happily help re-tension '
            'the chain if spares are approved.',
        'isSynthetic': true,
        'createdAt': '2026-09-27T11:48:00.000',
      },
    ],
    'isSynthetic': true,
  },
  {
    'id': 'seed-post-03',
    'title': 'Community recycling drop-off morning — volunteers wanted',
    'body': 'Planning a Saturday morning drop-off for soft plastics, batteries '
        'and e-waste at the shared open space. Two more volunteers to help sort '
        'and one person with a ute would make it work.',
    'category': 'Events',
    'precinct': 'Precinct A',
    'authorLabel': 'Resident A-21',
    'createdAt': '2026-09-28T10:00:00.000',
    'upvotes': 34,
    'comments': [
      {
        'id': 'seed-cmt-03-1',
        'authorLabel': 'Resident A-04',
        'body': 'I can cover the first two hours. Will bring gloves and a '
            'couple of sorting crates.',
        'isSynthetic': true,
        'createdAt': '2026-09-28T10:44:00.000',
      },
      {
        'id': 'seed-cmt-03-2',
        'authorLabel': 'Resident B-15',
        'body': 'Cross-precinct helper here — happy to run the battery table.',
        'isSynthetic': true,
        'createdAt': '2026-09-28T15:20:00.000',
      },
    ],
    'isSynthetic': true,
  },
  {
    'id': 'seed-post-04',
    'title': 'Found: bunch of keys on a lanyard',
    'body': 'Picked up a small bunch of keys on a fabric lanyard, no tag or '
        'name on it. Handed a description of the keyring to the front desk; '
        'reply here if it sounds like yours and I will confirm the details.',
    'category': 'Lost & Found',
    'precinct': 'Precinct B',
    'authorLabel': 'Resident B-02',
    'createdAt': '2026-09-30T17:45:00.000',
    'upvotes': 12,
    'comments': [
      {
        'id': 'seed-cmt-04-1',
        'authorLabel': 'Resident B-19',
        'body': 'Could be mine — lost them walking the dog. Does the lanyard '
            'have a bottle opener on it?',
        'isSynthetic': true,
        'createdAt': '2026-09-30T18:30:00.000',
      },
      {
        'id': 'seed-cmt-04-2',
        'authorLabel': 'Resident B-02',
        'body': 'It does. Marking as matched — pickup sorted privately.',
        'isSynthetic': true,
        'createdAt': '2026-09-30T20:02:00.000',
      },
    ],
    'isSynthetic': true,
  },
  {
    'id': 'seed-post-05',
    'title': 'Tree planting along the shared green strip',
    'body': 'The bare section of the green strip bakes in summer and the '
        'groundwater drains straight off. Proposing a small planting of '
        'climate-suitable natives plus a mulch ring.',
    'category': 'Sustainability',
    'precinct': 'Precinct A',
    'authorLabel': 'Resident A-09',
    'createdAt': '2026-10-03T09:10:00.000',
    'upvotes': 41,
    'comments': [
      {
        'id': 'seed-cmt-05-1',
        'authorLabel': 'Resident A-12',
        'body': 'Great idea. Natives that handle dry spells will survive the '
            'first summer without daily watering.',
        'isSynthetic': true,
        'createdAt': '2026-10-03T12:26:00.000',
      },
      {
        'id': 'seed-cmt-05-2',
        'authorLabel': 'Resident B-07',
        'body': 'Can we line it up with the recycling morning so we only need '
            'one set of permits?',
        'isSynthetic': true,
        'createdAt': '2026-10-04T08:50:00.000',
      },
    ],
    'isSynthetic': true,
  },
  {
    'id': 'seed-post-06',
    'title': 'Blocked stormwater drain before the next rain',
    'body': 'The drain grate on the low side of the shared open space is '
        'packed with leaves and grass clippings. Water pooled about knee-deep '
        'last storm and crept towards the path.',
    'category': 'Facilities',
    'precinct': 'Precinct B',
    'authorLabel': 'Resident B-11',
    'createdAt': '2026-10-05T07:35:00.000',
    'upvotes': 23,
    'comments': [
      {
        'id': 'seed-cmt-06-1',
        'authorLabel': 'Resident B-19',
        'body': 'Cleared the surface layer with a rake this evening — still '
            'needs a proper clean-out below the grate.',
        'isSynthetic': true,
        'createdAt': '2026-10-05T19:15:00.000',
      },
      {
        'id': 'seed-cmt-06-2',
        'authorLabel': 'Resident A-21',
        'body': 'Worth flagging that the pool blocks the accessible path. '
            'Logging it as a safety follow-up too.',
        'isSynthetic': true,
        'createdAt': '2026-10-06T09:40:00.000',
      },
    ],
    'isSynthetic': true,
  },
  {
    'id': 'seed-post-07',
    'title': 'Night lighting on the walkway is out again',
    'body': 'Two of the four lamps on the connecting walkway have been dark '
        'for over a week. It is a genuinely uncomfortable stretch to walk '
        'after the last bus.',
    'category': 'Safety',
    'precinct': 'Precinct A',
    'authorLabel': 'Resident A-15',
    'createdAt': '2026-10-07T21:05:00.000',
    'upvotes': 30,
    'comments': [
      {
        'id': 'seed-cmt-07-1',
        'authorLabel': 'Resident A-04',
        'body': 'Same stretch — counted three dark lamps on Tuesday night.',
        'isSynthetic': true,
        'createdAt': '2026-10-08T06:55:00.000',
      },
      {
        'id': 'seed-cmt-07-2',
        'authorLabel': 'Resident B-15',
        'body': 'If it is a photocell issue the whole run might need swapping '
            'at once rather than lamp by lamp.',
        'isSynthetic': true,
        'createdAt': '2026-10-08T17:30:00.000',
      },
    ],
    'isSynthetic': true,
  },
  {
    'id': 'seed-post-08',
    'title': 'Bin collection timing shifted — anyone else caught out?',
    'body': 'Collection moved about an hour earlier this fortnight, so half '
        'the street missed it. A short notice before timing changes would '
        'save a lot of smelly bins.',
    'category': 'Sustainability',
    'precinct': 'Precinct B',
    'authorLabel': 'Resident B-19',
    'createdAt': '2026-10-09T08:20:00.000',
    'upvotes': 16,
    'comments': [
      {
        'id': 'seed-cmt-08-1',
        'authorLabel': 'Resident B-11',
        'body': 'Yes — missed ours twice. A calendar entry pushed the day '
            'before would do it.',
        'isSynthetic': true,
        'createdAt': '2026-10-09T12:10:00.000',
      },
    ],
    'isSynthetic': true,
  },
];
