// SPDX-License-Identifier: Apache-2.0

///|
/// A byte range into the UTF-8 encoding of an episode body.
pub struct EvidenceSpan {
  priv episode_id : EpisodeId
  priv start_utf8 : Int
  priv end_utf8 : Int
  priv excerpt_digest : Digest256?
} derive(Eq, Compare)

///|
/// Construct a non-empty, non-negative byte range.
pub fn EvidenceSpan::new(
  episode_id : EpisodeId,
  start_utf8 : Int,
  end_utf8 : Int,
  excerpt_digest : Digest256?,
) -> EvidenceSpan raise MemoryError {
  if start_utf8 < 0 || end_utf8 <= start_utf8 {
    raise InvalidEvidence("evidence must be a non-empty non-negative range")
  }
  { episode_id, start_utf8, end_utf8, excerpt_digest }
}

///|
/// Return the referenced episode.
pub fn EvidenceSpan::episode_id(self : EvidenceSpan) -> EpisodeId {
  self.episode_id
}

///|
/// Return the inclusive UTF-8 byte offset.
pub fn EvidenceSpan::start_utf8(self : EvidenceSpan) -> Int {
  self.start_utf8
}

///|
/// Return the exclusive UTF-8 byte offset.
pub fn EvidenceSpan::end_utf8(self : EvidenceSpan) -> Int {
  self.end_utf8
}

///|
/// Return the optional digest of the cited excerpt.
pub fn EvidenceSpan::excerpt_digest(self : EvidenceSpan) -> Digest256? {
  self.excerpt_digest
}

///|
fn utf8_boundary(bytes : Bytes, offset : Int) -> Bool {
  if offset == 0 || offset == bytes.length() {
    true
  } else if offset < 0 || offset > bytes.length() {
    false
  } else {
    (bytes[offset].to_int() & 0xc0) != 0x80
  }
}

///|
/// Check this range against an episode body encoded as UTF-8 without a BOM.
pub fn EvidenceSpan::validate_for_body(
  self : EvidenceSpan,
  body : String,
) -> Unit raise MemoryError {
  let bytes = @utf8.encode(body, bom=false)
  if self.end_utf8 > bytes.length() {
    raise InvalidEvidence("evidence extends beyond the episode body")
  }
  if !utf8_boundary(bytes, self.start_utf8) ||
    !utf8_boundary(bytes, self.end_utf8) {
    raise InvalidEvidence(
      "evidence offsets must be UTF-8 code point boundaries",
    )
  }
}

///|
/// Canonical source references for a fact assertion.
pub struct Provenance {
  priv episode_ids : Array[EpisodeId]
  priv evidence : Array[EvidenceSpan]
  priv extractor : String?
} derive(Eq)

///|
/// Construct provenance, sorting and deduplicating both source collections.
pub fn Provenance::new(
  episode_ids : Array[EpisodeId],
  evidence : Array[EvidenceSpan],
  extractor : String?,
) -> Provenance raise MemoryError {
  if episode_ids.is_empty() {
    raise InvalidField("episode_ids", "must contain at least one episode")
  }
  match extractor {
    Some(value) if value.is_empty() =>
      raise InvalidField("extractor", "must not be empty when present")
    _ => ()
  }
  let normalized_ids = episode_ids.copy()
  normalized_ids.sort()
  normalized_ids.dedup()
  let normalized_evidence = evidence.copy()
  normalized_evidence.sort()
  normalized_evidence.dedup()
  for span in normalized_evidence {
    if !normalized_ids.contains(span.episode_id()) {
      raise InvalidEvidence("evidence episode is absent from episode_ids")
    }
  }
  { episode_ids: normalized_ids, evidence: normalized_evidence, extractor }
}

///|
/// Return a defensive copy of episode IDs in canonical order.
pub fn Provenance::episode_ids(self : Provenance) -> Array[EpisodeId] {
  self.episode_ids.copy()
}

///|
/// Return a defensive copy of evidence spans in canonical order.
pub fn Provenance::evidence(self : Provenance) -> Array[EvidenceSpan] {
  self.evidence.copy()
}

///|
/// Return the optional extractor label.
pub fn Provenance::extractor(self : Provenance) -> String? {
  self.extractor
}
