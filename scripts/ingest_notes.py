# DEPRECATED — gbrain handles ingestion natively.
#
# Use:
#   gbrain import /data/vault/notes/
#   gbrain embed --stale
#   gbrain extract links --source db
#
# For session transcripts, first convert JSONL to markdown:
#   python scripts/parse_transcripts.py /path/to/sessions/ --agent myagent \
#       --output /data/vault/transcripts/myagent/
#   gbrain import /data/vault/transcripts/myagent/
