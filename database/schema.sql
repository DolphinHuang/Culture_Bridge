-- Culture Bridge review draft. SQLite 3.37+; enable foreign keys on EVERY connection.
PRAGMA foreign_keys = ON;
BEGIN;

CREATE TABLE users (
  id TEXT PRIMARY KEY NOT NULL,
  auth_subject TEXT UNIQUE,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  nickname TEXT NOT NULL CHECK(length(trim(nickname)) BETWEEN 1 AND 40),
  preferred_locale TEXT NOT NULL DEFAULT 'zh-Hant' CHECK(preferred_locale IN ('zh-Hant','en')),
  role TEXT NOT NULL DEFAULT 'general' CHECK(role IN ('general','reviewer','admin')),
  is_team_member INTEGER NOT NULL DEFAULT 0 CHECK(is_team_member IN (0,1)),
  email_verified_at TEXT,
  is_suspended INTEGER NOT NULL DEFAULT 0 CHECK(is_suspended IN (0,1)),
  suspension_reason TEXT,
  push_notifications_enabled INTEGER NOT NULL DEFAULT 1 CHECK(push_notifications_enabled IN (0,1)),
  deleted_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CHECK((is_suspended = 0 AND suspension_reason IS NULL) OR
        (is_suspended = 1 AND suspension_reason IS NOT NULL))
);
CREATE TABLE institutions (
  id TEXT PRIMARY KEY NOT NULL,
  name_zh TEXT NOT NULL,
  name_en TEXT NOT NULL,
  city TEXT
);
CREATE TABLE topics (
  id TEXT PRIMARY KEY NOT NULL,
  name_zh TEXT NOT NULL,
  name_en TEXT NOT NULL
);
INSERT INTO topics VALUES
 ('life_adaptation','生活適應','Life adaptation'),
 ('culture_communication','文化與溝通','Culture & communication'),
 ('life','生活','Life'),
 ('campus','校園','Campus'),
 ('culture','文化','Culture');

-- PROCEDURES: identity of a task is separate from its historical versions.
CREATE TABLE actions (
  id TEXT PRIMARY KEY NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  archived_at TEXT
);
CREATE TABLE action_versions (
  id TEXT PRIMARY KEY NOT NULL,
  action_id TEXT NOT NULL REFERENCES actions(id),
  version_number INTEGER NOT NULL CHECK(version_number > 0),
  title_zh TEXT NOT NULL,
  title_en TEXT NOT NULL,
  description_zh TEXT NOT NULL DEFAULT '',
  description_en TEXT NOT NULL DEFAULT '',
  institution_id TEXT REFERENCES institutions(id),
  location TEXT,
  applicable_to TEXT NOT NULL,
  verification_status TEXT NOT NULL DEFAULT 'unverified'
    CHECK(verification_status IN ('unverified','community_supported','needs_review','verified','outdated')),
  published_at TEXT,
  created_by TEXT NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE(action_id,version_number)
);
CREATE TABLE action_steps (
  id TEXT PRIMARY KEY NOT NULL,
  action_version_id TEXT NOT NULL REFERENCES action_versions(id),
  position INTEGER NOT NULL CHECK(position > 0),
  title_zh TEXT NOT NULL,
  title_en TEXT NOT NULL,
  notes TEXT,
  UNIQUE(action_version_id,position),
  UNIQUE(action_version_id,id)
);
CREATE TABLE sources (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  url TEXT NOT NULL,
  publisher TEXT NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('official','institution','partner','ai_search','community')),
  accessed_at TEXT NOT NULL
);
CREATE TABLE action_version_sources (
  action_version_id TEXT NOT NULL REFERENCES action_versions(id),
  source_id TEXT NOT NULL REFERENCES sources(id),
  evidence_note TEXT NOT NULL,
  PRIMARY KEY(action_version_id,source_id)
);
CREATE TABLE verification_records (
  id TEXT PRIMARY KEY NOT NULL,
  action_version_id TEXT NOT NULL REFERENCES action_versions(id),
  source_id TEXT NOT NULL,
  reviewer_id TEXT NOT NULL REFERENCES users(id),
  decision TEXT NOT NULL CHECK(decision IN ('verified','needs_review','outdated')),
  note TEXT NOT NULL,
  checked_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  FOREIGN KEY(action_version_id,source_id)
    REFERENCES action_version_sources(action_version_id,source_id)
);

-- Each attempt pins the version the student actually saw, even after updates.
CREATE TABLE executions (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id),
  action_version_id TEXT NOT NULL REFERENCES action_versions(id),
  institution_id TEXT REFERENCES institutions(id),
  identity_type TEXT NOT NULL CHECK(identity_type IN ('degree_student','exchange_student','language_student','other')),
  started_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  finished_at TEXT,
  outcome TEXT CHECK(outcome IN ('success','failed','different','abandoned')),
  CHECK((outcome IS NULL AND finished_at IS NULL) OR (outcome IS NOT NULL AND finished_at IS NOT NULL)),
  CHECK(finished_at IS NULL OR finished_at >= started_at),
  UNIQUE(id,action_version_id)
);
CREATE TABLE execution_steps (
  execution_id TEXT NOT NULL,
  action_version_id TEXT NOT NULL,
  step_id TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','done','stuck')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  PRIMARY KEY(execution_id,step_id),
  FOREIGN KEY(execution_id,action_version_id) REFERENCES executions(id,action_version_id),
  FOREIGN KEY(action_version_id,step_id) REFERENCES action_steps(action_version_id,id)
);
CREATE TABLE execution_feedback (
  id TEXT PRIMARY KEY NOT NULL,
  execution_id TEXT NOT NULL,
  action_version_id TEXT NOT NULL,
  step_id TEXT,
  kind TEXT NOT NULL CHECK(kind IN ('stuck','different','possibly_outdated')),
  category TEXT CHECK(category IN ('documents','fee','location','process','eligibility','website','other')),
  original_voice TEXT,
  review_state TEXT NOT NULL DEFAULT 'pending' CHECK(review_state IN ('pending','reviewed','dismissed')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  FOREIGN KEY(execution_id,action_version_id) REFERENCES executions(id,action_version_id),
  FOREIGN KEY(action_version_id,step_id) REFERENCES action_steps(action_version_id,id),
  CHECK(kind <> 'stuck' OR step_id IS NOT NULL)
);

-- EXPERIENCES: never carry a factual verification/truth score.
CREATE TABLE experiences (
  id TEXT PRIMARY KEY NOT NULL,
  author_id TEXT NOT NULL REFERENCES users(id),
  topic_id TEXT NOT NULL REFERENCES topics(id),
  identity_type TEXT NOT NULL CHECK(identity_type IN ('degree_student','exchange_student','language_student','other')),
  original_voice TEXT NOT NULL CHECK(length(trim(original_voice)) BETWEEN 1 AND 2000),
  source_locale TEXT NOT NULL DEFAULT 'zh-Hant' CHECK(source_locale IN ('zh-Hant','en')),
  institution_id TEXT REFERENCES institutions(id),
  location TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','hidden')),
  confirmed_summary_id TEXT,
  published_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  FOREIGN KEY(id,confirmed_summary_id) REFERENCES experience_summaries(experience_id,id)
    DEFERRABLE INITIALLY DEFERRED,
  CHECK(status <> 'published' OR (confirmed_summary_id IS NOT NULL AND published_at IS NOT NULL))
);
CREATE TABLE experience_summaries (
  id TEXT PRIMARY KEY NOT NULL,
  experience_id TEXT NOT NULL REFERENCES experiences(id),
  version_number INTEGER NOT NULL CHECK(version_number > 0),
  source_voice TEXT NOT NULL,
  situation TEXT NOT NULL,
  feeling_or_attempt TEXT NOT NULL,
  reminder TEXT NOT NULL,
  model_name TEXT NOT NULL,
  confirmed_by TEXT REFERENCES users(id),
  confirmed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CHECK((confirmed_by IS NULL AND confirmed_at IS NULL) OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL)),
  UNIQUE(experience_id,version_number),
  UNIQUE(experience_id,id)
);
CREATE TABLE experience_translations (
  experience_id TEXT NOT NULL REFERENCES experiences(id),
  summary_id TEXT NOT NULL,
  locale TEXT NOT NULL CHECK(locale IN ('zh-Hant','en')),
  original_voice TEXT NOT NULL,
  situation TEXT NOT NULL,
  feeling_or_attempt TEXT NOT NULL,
  reminder TEXT NOT NULL,
  method TEXT NOT NULL CHECK(method IN ('human','ai')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  PRIMARY KEY(experience_id,summary_id,locale),
  FOREIGN KEY(experience_id,summary_id) REFERENCES experience_summaries(experience_id,id)
);
CREATE TABLE experience_reactions (
  experience_id TEXT NOT NULL REFERENCES experiences(id),
  user_id TEXT NOT NULL REFERENCES users(id),
  kind TEXT NOT NULL CHECK(kind IN ('helpful','experienced_too')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  PRIMARY KEY(experience_id,user_id,kind)
);
-- A different experience is a full authored story, not just another like.
CREATE TABLE experience_links (
  from_experience_id TEXT NOT NULL REFERENCES experiences(id),
  to_experience_id TEXT NOT NULL REFERENCES experiences(id),
  kind TEXT NOT NULL CHECK(kind IN ('similar','different')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  PRIMARY KEY(from_experience_id,to_experience_id,kind),
  CHECK(from_experience_id <> to_experience_id)
);
CREATE TABLE action_experience_links (
  action_id TEXT NOT NULL REFERENCES actions(id),
  experience_id TEXT NOT NULL REFERENCES experiences(id),
  PRIMARY KEY(action_id,experience_id)
);

-- COMMUNITY: posts and replies are separate from experience cards and verified procedures.
CREATE TABLE community_posts (
  id TEXT PRIMARY KEY NOT NULL,
  author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  topic_id TEXT NOT NULL REFERENCES topics(id),
  title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 60),
  body TEXT NOT NULL CHECK(length(trim(body)) BETWEEN 1 AND 2000),
  locale TEXT NOT NULL DEFAULT 'zh-Hant' CHECK(locale IN ('zh-Hant','en')),
  status TEXT NOT NULL DEFAULT 'published' CHECK(status IN ('published','hidden','deleted')),
  is_official INTEGER NOT NULL DEFAULT 0 CHECK(is_official IN (0,1)),
  is_edited INTEGER NOT NULL DEFAULT 0 CHECK(is_edited IN (0,1)),
  possible_error_flag INTEGER NOT NULL DEFAULT 0 CHECK(possible_error_flag IN (0,1)),
  hidden_at TEXT,
  deleted_at TEXT,
  published_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CHECK((status <> 'hidden' AND hidden_at IS NULL) OR (status = 'hidden' AND hidden_at IS NOT NULL) OR status = 'deleted'),
  CHECK((status <> 'deleted' AND deleted_at IS NULL) OR (status = 'deleted' AND deleted_at IS NOT NULL))
);
CREATE TABLE community_comments (
  id TEXT PRIMARY KEY NOT NULL,
  post_id TEXT NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  parent_comment_id TEXT,
  body TEXT NOT NULL CHECK(length(trim(body)) BETWEEN 1 AND 500),
  status TEXT NOT NULL DEFAULT 'published' CHECK(status IN ('published','hidden','deleted')),
  is_edited INTEGER NOT NULL DEFAULT 0 CHECK(is_edited IN (0,1)),
  possible_error_flag INTEGER NOT NULL DEFAULT 0 CHECK(possible_error_flag IN (0,1)),
  hidden_at TEXT,
  deleted_at TEXT,
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE(post_id,id),
  FOREIGN KEY(post_id,parent_comment_id) REFERENCES community_comments(post_id,id) ON DELETE CASCADE,
  CHECK(parent_comment_id IS NULL OR parent_comment_id <> id),
  CHECK((status <> 'hidden' AND hidden_at IS NULL) OR (status = 'hidden' AND hidden_at IS NOT NULL) OR status = 'deleted'),
  CHECK((status <> 'deleted' AND deleted_at IS NULL) OR (status = 'deleted' AND deleted_at IS NOT NULL))
);
CREATE TABLE content_ratings (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type TEXT NOT NULL CHECK(target_type IN ('post','comment','reply')),
  target_id TEXT NOT NULL,
  vote TEXT NOT NULL CHECK(vote IN ('correct','incorrect')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  PRIMARY KEY(user_id,target_type,target_id)
);
CREATE TABLE post_source_checks (
  id TEXT PRIMARY KEY NOT NULL,
  post_id TEXT NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  summary TEXT,
  summary_locale TEXT NOT NULL DEFAULT 'zh-Hant' CHECK(summary_locale IN ('zh-Hant','en')),
  status TEXT NOT NULL DEFAULT 'checking' CHECK(status IN ('checking','ready','no_sources','failed','deferred')),
  retry_count INTEGER NOT NULL DEFAULT 0 CHECK(retry_count BETWEEN 0 AND 2),
  checked_at TEXT,
  based_on_title TEXT NOT NULL,
  based_on_body TEXT NOT NULL,
  based_on_post_updated_at TEXT NOT NULL,
  stale_after_edit INTEGER NOT NULL DEFAULT 0 CHECK(stale_after_edit IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CHECK(status <> 'ready' OR (summary IS NOT NULL AND checked_at IS NOT NULL)),
  CHECK(status IN ('checking','failed','deferred') OR checked_at IS NOT NULL)
);
CREATE TABLE post_source_check_sources (
  source_check_id TEXT NOT NULL REFERENCES post_source_checks(id) ON DELETE CASCADE,
  source_id TEXT NOT NULL REFERENCES sources(id),
  position INTEGER NOT NULL CHECK(position BETWEEN 1 AND 3),
  PRIMARY KEY(source_check_id,position),
  UNIQUE(source_check_id,source_id)
);
CREATE TABLE user_blocks (
  blocker_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  PRIMARY KEY(blocker_id,blocked_id),
  CHECK(blocker_id <> blocked_id)
);
CREATE TABLE reports (
  id TEXT PRIMARY KEY NOT NULL,
  reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type TEXT NOT NULL CHECK(target_type IN ('post','comment','reply','source_check')),
  target_id TEXT NOT NULL,
  reason TEXT NOT NULL CHECK(reason IN ('misinformation','harassment_discrimination','spam','inappropriate','other')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','substantiated','dismissed')),
  handled_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  handled_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE(reporter_id,target_type,target_id),
  CHECK((status = 'pending' AND handled_by IS NULL AND handled_at IS NULL) OR
        (status <> 'pending' AND handled_at IS NOT NULL))
);
CREATE TABLE review_rules (
  id TEXT PRIMARY KEY NOT NULL,
  min_total_votes INTEGER NOT NULL CHECK(min_total_votes > 0),
  incorrect_ratio REAL NOT NULL CHECK(incorrect_ratio > 0 AND incorrect_ratio <= 1),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
INSERT INTO review_rules(id,min_total_votes,incorrect_ratio) VALUES('default',10,0.15);
CREATE TABLE review_queue (
  id TEXT PRIMARY KEY NOT NULL,
  target_type TEXT NOT NULL CHECK(target_type IN ('post','comment','reply')),
  target_id TEXT NOT NULL,
  trigger_reason TEXT NOT NULL CHECK(trigger_reason IN ('rating_threshold','report')),
  state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','confirmed_correct','hidden','deleted','dismissed')),
  total_votes INTEGER NOT NULL DEFAULT 0 CHECK(total_votes >= 0),
  incorrect_votes INTEGER NOT NULL DEFAULT 0 CHECK(incorrect_votes >= 0 AND incorrect_votes <= total_votes),
  reviewer_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  resolved_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE(target_type,target_id),
  CHECK((state = 'pending' AND reviewer_id IS NULL AND resolved_at IS NULL) OR
        (state <> 'pending' AND resolved_at IS NOT NULL))
);
CREATE TABLE notifications (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  actor_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  type TEXT NOT NULL CHECK(type IN ('post_commented','comment_replied','report_substantiated','suspended','system')),
  target_type TEXT CHECK(target_type IN ('post','comment','reply','source_check','user')),
  target_id TEXT,
  body TEXT NOT NULL,
  read_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE TABLE push_tokens (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL CHECK(platform IN ('ios','android','web')),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE TABLE email_tokens (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK(kind IN ('email_verification','password_reset')),
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CHECK(consumed_at IS NULL OR consumed_at <= expires_at)
);

-- Publication gates: confirmation must be by the author and for this exact voice.
CREATE TRIGGER validate_experience_publication_insert BEFORE INSERT ON experiences
WHEN NEW.status = 'published'
BEGIN
 SELECT CASE WHEN NOT EXISTS (
  SELECT 1 FROM experience_summaries s WHERE s.id = NEW.confirmed_summary_id
    AND s.experience_id = NEW.id AND s.confirmed_by = NEW.author_id
    AND s.confirmed_at IS NOT NULL AND s.source_voice = NEW.original_voice
 ) THEN RAISE(ABORT,'Author must confirm a summary of the current original voice') END;
END;
CREATE TRIGGER validate_experience_publication_update BEFORE UPDATE ON experiences
WHEN NEW.status = 'published'
BEGIN
 SELECT CASE WHEN NOT EXISTS (
  SELECT 1 FROM experience_summaries s WHERE s.id = NEW.confirmed_summary_id
    AND s.experience_id = NEW.id AND s.confirmed_by = NEW.author_id
    AND s.confirmed_at IS NOT NULL AND s.source_voice = NEW.original_voice
 ) THEN RAISE(ABORT,'Author must confirm a summary of the current original voice') END;
END;
CREATE TRIGGER protect_published_summary BEFORE UPDATE ON experience_summaries
WHEN EXISTS (SELECT 1 FROM experiences e WHERE e.status = 'published' AND e.confirmed_summary_id = OLD.id)
BEGIN
 SELECT RAISE(ABORT,'Create a new summary version rather than edit a published summary');
END;
CREATE TRIGGER validate_verification_insert BEFORE INSERT ON action_versions
WHEN NEW.verification_status = 'verified'
BEGIN
 SELECT RAISE(ABORT,'Create version and source evidence before marking it verified');
END;
CREATE TRIGGER validate_verification_update BEFORE UPDATE OF verification_status ON action_versions
WHEN NEW.verification_status = 'verified'
BEGIN
 SELECT CASE WHEN NOT EXISTS (
  SELECT 1 FROM verification_records v JOIN users u ON u.id = v.reviewer_id
  WHERE v.action_version_id = NEW.id AND u.role IN ('reviewer','admin') AND v.decision = 'verified'
 ) THEN RAISE(ABORT,'Verification requires reviewer evidence') END;
END;
-- Published procedure content is versioned rather than rewritten in place.
CREATE TRIGGER freeze_version_content BEFORE UPDATE ON action_versions
WHEN OLD.published_at IS NOT NULL AND (
 NEW.action_id IS NOT OLD.action_id OR NEW.version_number IS NOT OLD.version_number OR
 NEW.title_zh IS NOT OLD.title_zh OR NEW.title_en IS NOT OLD.title_en OR
 NEW.description_zh IS NOT OLD.description_zh OR NEW.description_en IS NOT OLD.description_en OR
 NEW.applicable_to IS NOT OLD.applicable_to OR NEW.institution_id IS NOT OLD.institution_id OR
 NEW.location IS NOT OLD.location OR NEW.published_at IS NOT OLD.published_at)
BEGIN SELECT RAISE(ABORT,'Published procedure content requires a new version'); END;
CREATE TRIGGER freeze_step_insert BEFORE INSERT ON action_steps
WHEN EXISTS(SELECT 1 FROM action_versions WHERE id = NEW.action_version_id AND published_at IS NOT NULL)
BEGIN SELECT RAISE(ABORT,'Published steps require a new action version'); END;
CREATE TRIGGER freeze_step_update BEFORE UPDATE ON action_steps
WHEN EXISTS(SELECT 1 FROM action_versions WHERE id IN (OLD.action_version_id,NEW.action_version_id) AND published_at IS NOT NULL)
BEGIN SELECT RAISE(ABORT,'Published steps require a new action version'); END;
CREATE TRIGGER freeze_step_delete BEFORE DELETE ON action_steps
WHEN EXISTS(SELECT 1 FROM action_versions WHERE id = OLD.action_version_id AND published_at IS NOT NULL)
BEGIN SELECT RAISE(ABORT,'Published steps require a new action version'); END;
CREATE TRIGGER validate_execution_version BEFORE INSERT ON executions
WHEN NOT EXISTS(SELECT 1 FROM action_versions WHERE id = NEW.action_version_id AND published_at IS NOT NULL)
BEGIN SELECT RAISE(ABORT,'Students can only start published procedure versions'); END;

CREATE TRIGGER validate_comment_depth_insert BEFORE INSERT ON community_comments
WHEN NEW.parent_comment_id IS NOT NULL AND EXISTS(
 SELECT 1 FROM community_comments parent
 WHERE parent.id = NEW.parent_comment_id AND parent.parent_comment_id IS NOT NULL
)
BEGIN SELECT RAISE(ABORT,'Replies cannot be replied to'); END;
CREATE TRIGGER validate_comment_depth_update BEFORE UPDATE OF parent_comment_id ON community_comments
WHEN NEW.parent_comment_id IS NOT NULL AND EXISTS(
 SELECT 1 FROM community_comments parent
 WHERE parent.id = NEW.parent_comment_id AND parent.parent_comment_id IS NOT NULL
)
BEGIN SELECT RAISE(ABORT,'Replies cannot be replied to'); END;
CREATE TRIGGER mark_post_edited AFTER UPDATE OF title,body ON community_posts
WHEN OLD.title IS NOT NEW.title OR OLD.body IS NOT NEW.body
BEGIN
 UPDATE community_posts SET is_edited=1,updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=NEW.id;
 UPDATE post_source_checks SET stale_after_edit=1 WHERE post_id=NEW.id;
END;
CREATE TRIGGER mark_comment_edited AFTER UPDATE OF body ON community_comments
WHEN OLD.body IS NOT NEW.body
BEGIN
 UPDATE community_comments SET is_edited=1,updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=NEW.id;
END;
CREATE TRIGGER validate_rating_insert BEFORE INSERT ON content_ratings
BEGIN
 SELECT CASE WHEN NEW.target_type='post' AND NOT EXISTS(
  SELECT 1 FROM community_posts WHERE id=NEW.target_id
 ) THEN RAISE(ABORT,'Rating target post does not exist') END;
 SELECT CASE WHEN NEW.target_type='comment' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NULL
 ) THEN RAISE(ABORT,'Rating target comment does not exist') END;
 SELECT CASE WHEN NEW.target_type='reply' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NOT NULL
 ) THEN RAISE(ABORT,'Rating target reply does not exist') END;
 SELECT CASE WHEN NEW.target_type='post' AND EXISTS(
  SELECT 1 FROM community_posts WHERE id=NEW.target_id AND author_id=NEW.user_id
 ) THEN RAISE(ABORT,'Authors cannot rate their own content') END;
 SELECT CASE WHEN NEW.target_type IN ('comment','reply') AND EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND author_id=NEW.user_id
 ) THEN RAISE(ABORT,'Authors cannot rate their own content') END;
END;
CREATE TRIGGER validate_rating_update BEFORE UPDATE ON content_ratings
BEGIN
 SELECT CASE WHEN NEW.target_type='post' AND NOT EXISTS(
  SELECT 1 FROM community_posts WHERE id=NEW.target_id
 ) THEN RAISE(ABORT,'Rating target post does not exist') END;
 SELECT CASE WHEN NEW.target_type='comment' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NULL
 ) THEN RAISE(ABORT,'Rating target comment does not exist') END;
 SELECT CASE WHEN NEW.target_type='reply' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NOT NULL
 ) THEN RAISE(ABORT,'Rating target reply does not exist') END;
 SELECT CASE WHEN NEW.target_type='post' AND EXISTS(
  SELECT 1 FROM community_posts WHERE id=NEW.target_id AND author_id=NEW.user_id
 ) THEN RAISE(ABORT,'Authors cannot rate their own content') END;
 SELECT CASE WHEN NEW.target_type IN ('comment','reply') AND EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND author_id=NEW.user_id
 ) THEN RAISE(ABORT,'Authors cannot rate their own content') END;
END;
CREATE TRIGGER validate_report_insert BEFORE INSERT ON reports
BEGIN
 SELECT CASE WHEN NEW.target_type='post' AND NOT EXISTS(
  SELECT 1 FROM community_posts WHERE id=NEW.target_id
 ) THEN RAISE(ABORT,'Report target post does not exist') END;
 SELECT CASE WHEN NEW.target_type='comment' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NULL
 ) THEN RAISE(ABORT,'Report target comment does not exist') END;
 SELECT CASE WHEN NEW.target_type='reply' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NOT NULL
 ) THEN RAISE(ABORT,'Report target reply does not exist') END;
 SELECT CASE WHEN NEW.target_type='source_check' AND NOT EXISTS(
  SELECT 1 FROM post_source_checks WHERE id=NEW.target_id
 ) THEN RAISE(ABORT,'Report target source check does not exist') END;
END;
CREATE TRIGGER validate_report_update BEFORE UPDATE ON reports
BEGIN
 SELECT CASE WHEN NEW.target_type='post' AND NOT EXISTS(
  SELECT 1 FROM community_posts WHERE id=NEW.target_id
 ) THEN RAISE(ABORT,'Report target post does not exist') END;
 SELECT CASE WHEN NEW.target_type='comment' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NULL
 ) THEN RAISE(ABORT,'Report target comment does not exist') END;
 SELECT CASE WHEN NEW.target_type='reply' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NOT NULL
 ) THEN RAISE(ABORT,'Report target reply does not exist') END;
 SELECT CASE WHEN NEW.target_type='source_check' AND NOT EXISTS(
  SELECT 1 FROM post_source_checks WHERE id=NEW.target_id
 ) THEN RAISE(ABORT,'Report target source check does not exist') END;
END;
CREATE TRIGGER validate_review_queue_insert BEFORE INSERT ON review_queue
BEGIN
 SELECT CASE WHEN NEW.target_type='post' AND NOT EXISTS(
  SELECT 1 FROM community_posts WHERE id=NEW.target_id
 ) THEN RAISE(ABORT,'Review target post does not exist') END;
 SELECT CASE WHEN NEW.target_type='comment' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NULL
 ) THEN RAISE(ABORT,'Review target comment does not exist') END;
 SELECT CASE WHEN NEW.target_type='reply' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NOT NULL
 ) THEN RAISE(ABORT,'Review target reply does not exist') END;
END;
CREATE TRIGGER validate_review_queue_update BEFORE UPDATE ON review_queue
BEGIN
 SELECT CASE WHEN NEW.target_type='post' AND NOT EXISTS(
  SELECT 1 FROM community_posts WHERE id=NEW.target_id
 ) THEN RAISE(ABORT,'Review target post does not exist') END;
 SELECT CASE WHEN NEW.target_type='comment' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NULL
 ) THEN RAISE(ABORT,'Review target comment does not exist') END;
 SELECT CASE WHEN NEW.target_type='reply' AND NOT EXISTS(
  SELECT 1 FROM community_comments WHERE id=NEW.target_id AND parent_comment_id IS NOT NULL
 ) THEN RAISE(ABORT,'Review target reply does not exist') END;
END;
CREATE TRIGGER validate_email_token_expiry_insert BEFORE INSERT ON email_tokens
WHEN julianday(NEW.expires_at) <= julianday(NEW.created_at)
  OR julianday(NEW.expires_at) > julianday(NEW.created_at) + 1
BEGIN SELECT RAISE(ABORT,'Email tokens expire within 24 hours'); END;
CREATE TRIGGER validate_email_token_expiry_update BEFORE UPDATE OF expires_at,created_at ON email_tokens
WHEN julianday(NEW.expires_at) <= julianday(NEW.created_at)
  OR julianday(NEW.expires_at) > julianday(NEW.created_at) + 1
BEGIN SELECT RAISE(ABORT,'Email tokens expire within 24 hours'); END;
CREATE TRIGGER cleanup_post_targets BEFORE DELETE ON community_posts
BEGIN
 DELETE FROM content_ratings WHERE target_type='post' AND target_id=OLD.id;
 DELETE FROM content_ratings
  WHERE target_type IN ('comment','reply')
    AND target_id IN (SELECT id FROM community_comments WHERE post_id=OLD.id);
 DELETE FROM reports WHERE target_type='post' AND target_id=OLD.id;
 DELETE FROM reports
  WHERE target_type IN ('comment','reply')
    AND target_id IN (SELECT id FROM community_comments WHERE post_id=OLD.id);
 DELETE FROM reports
  WHERE target_type='source_check'
    AND target_id IN (SELECT id FROM post_source_checks WHERE post_id=OLD.id);
 DELETE FROM review_queue WHERE target_type='post' AND target_id=OLD.id;
 DELETE FROM review_queue
  WHERE target_type IN ('comment','reply')
    AND target_id IN (SELECT id FROM community_comments WHERE post_id=OLD.id);
END;
CREATE TRIGGER cleanup_comment_targets BEFORE DELETE ON community_comments
BEGIN
 DELETE FROM content_ratings
  WHERE target_type IN ('comment','reply')
    AND target_id IN (SELECT id FROM community_comments WHERE id=OLD.id OR parent_comment_id=OLD.id);
 DELETE FROM reports
  WHERE target_type IN ('comment','reply')
    AND target_id IN (SELECT id FROM community_comments WHERE id=OLD.id OR parent_comment_id=OLD.id);
 DELETE FROM review_queue
  WHERE target_type IN ('comment','reply')
    AND target_id IN (SELECT id FROM community_comments WHERE id=OLD.id OR parent_comment_id=OLD.id);
END;
CREATE TRIGGER cleanup_source_check_targets BEFORE DELETE ON post_source_checks
BEGIN
 DELETE FROM reports WHERE target_type='source_check' AND target_id=OLD.id;
END;

CREATE INDEX idx_action_versions_published ON action_versions(action_id,published_at,version_number);
CREATE INDEX idx_executions_recent ON executions(action_version_id,finished_at,outcome);
CREATE INDEX idx_executions_user ON executions(user_id,started_at);
CREATE INDEX idx_feedback_step ON execution_feedback(action_version_id,step_id,kind,created_at);
CREATE INDEX idx_experiences_explore ON experiences(status,topic_id,identity_type,published_at);
CREATE INDEX idx_experiences_author ON experiences(author_id,status);
CREATE INDEX idx_links_reverse ON experience_links(to_experience_id,kind);
CREATE INDEX idx_reactions_user ON experience_reactions(user_id,kind);
CREATE INDEX idx_verifications_version ON verification_records(action_version_id,checked_at);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role,is_suspended);
CREATE INDEX idx_posts_feed ON community_posts(status,topic_id,published_at);
CREATE INDEX idx_posts_official ON community_posts(is_official,status,published_at);
CREATE INDEX idx_posts_author ON community_posts(author_id,status,created_at);
CREATE INDEX idx_posts_title_search ON community_posts(title);
CREATE INDEX idx_posts_body_search ON community_posts(body);
CREATE INDEX idx_comments_post ON community_comments(post_id,parent_comment_id,created_at);
CREATE INDEX idx_comments_author ON community_comments(author_id,status,created_at);
CREATE INDEX idx_ratings_target ON content_ratings(target_type,target_id,vote);
CREATE INDEX idx_source_checks_post ON post_source_checks(post_id,status,checked_at);
CREATE INDEX idx_blocks_blocked ON user_blocks(blocked_id,blocker_id);
CREATE INDEX idx_reports_queue ON reports(status,reason,created_at);
CREATE INDEX idx_reports_target ON reports(target_type,target_id);
CREATE INDEX idx_review_queue_state ON review_queue(state,created_at);
CREATE INDEX idx_notifications_user ON notifications(user_id,read_at,created_at);
CREATE INDEX idx_push_tokens_user ON push_tokens(user_id,enabled);
CREATE INDEX idx_email_tokens_user ON email_tokens(user_id,kind,expires_at);

-- PostgreSQL production migration notes:
-- CREATE EXTENSION IF NOT EXISTS vector;
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- CREATE INDEX idx_posts_title_trgm ON community_posts USING gin (title gin_trgm_ops);
-- CREATE INDEX idx_posts_body_trgm ON community_posts USING gin (body gin_trgm_ops);
-- Keep vector columns out of this B-owned draft unless they belong to a non-D table.

-- Public projection intentionally excludes author_id and optional identifying context.
CREATE VIEW public_experiences AS
 SELECT e.id,e.topic_id,e.identity_type,e.original_voice,e.source_locale,e.published_at,
        s.id AS summary_id,s.situation,s.feeling_or_attempt,s.reminder,s.confirmed_at,
        (SELECT count(*) FROM experience_reactions r WHERE r.experience_id=e.id AND r.kind='helpful') AS helpful_count,
        (SELECT count(*) FROM experience_links l JOIN experiences other ON other.id=l.to_experience_id
          WHERE l.from_experience_id=e.id AND l.kind='different' AND other.status='published') AS different_count
 FROM experiences e JOIN experience_summaries s ON s.id=e.confirmed_summary_id AND s.experience_id=e.id
 WHERE e.status='published';

CREATE VIEW latest_published_actions AS
 SELECT v.* FROM action_versions v
 WHERE v.published_at IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM action_versions newer WHERE newer.action_id=v.action_id
   AND newer.published_at IS NOT NULL AND newer.version_number>v.version_number
 ) AND EXISTS(SELECT 1 FROM actions a WHERE a.id=v.action_id AND a.archived_at IS NULL);
COMMIT;
