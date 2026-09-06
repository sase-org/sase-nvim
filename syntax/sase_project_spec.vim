" Vim syntax file
" Language:    SASE ProjectSpec (.sase)
" Maintainer:  Bryan Bugyi
" Filetype:    sase_project_spec

if exists("b:current_syntax")
  finish
endif

syn case match

" ==========================================================================
" Syntax Groups
" ==========================================================================

" --- Field Labels (column 0) ---
syn match saseProjectSpecFieldLabel /^NAME:/
syn match saseProjectSpecFieldLabel /^DESCRIPTION:/
syn match saseProjectSpecFieldLabel /^STATUS:/
syn match saseProjectSpecFieldLabel /^PARENT:/
syn match saseProjectSpecFieldLabel /^CL:/
syn match saseProjectSpecFieldLabel /^PR:/
syn match saseProjectSpecFieldLabel /^PR_ORIGIN:/
syn match saseProjectSpecFieldLabel /^BUG:/
syn match saseProjectSpecFieldLabel /^REFS:/
syn match saseProjectSpecFieldLabel /^TEST TARGETS:/
syn match saseProjectSpecFieldLabel /^KICKSTART:/
syn match saseProjectSpecFieldLabel /^STITCHES:/
syn match saseProjectSpecFieldLabel /^COMMITS:/
syn match saseProjectSpecFieldLabel /^HOOKS:/
syn match saseProjectSpecFieldLabel /^COMMENTS:/
syn match saseProjectSpecFieldLabel /^MENTORS:/
syn match saseProjectSpecFieldLabel /^RUNNING:/
syn match saseProjectSpecFieldLabel /^TIMESTAMPS:/
syn match saseProjectSpecFieldLabel /^DELTAS:/
syn match saseProjectSpecFieldLabel /^WORKSPACE_DIR:/

" --- WORKSPACE_DIR value ---
syn match saseProjectSpecFilePath /\%(^WORKSPACE_DIR: \)\@<=.\+/

" --- RUNNING entries: #N | PID | workflow | cl_name | timestamp ---
syn match saseProjectSpecRunningWorkspace /^\s\+#\d\+/
syn match saseProjectSpecRunningPipe /\s|\s/
syn match saseProjectSpecRunningPinned /\<PINNED\>/

" --- Sub-entry field labels (| CHAT: , | DIFF:) ---
syn match saseProjectSpecSubFieldLabel /|\s\+\zs\%(CHAT\|DIFF\|PLAN\):/

" --- NAME value ---
syn match saseProjectSpecNameValue /\%(^NAME: \)\@<=.\+/

" --- STATUS values (each gets its own color) ---
syn match saseProjectSpecStatusWIP       /\%(^STATUS: \)\@<=WIP/
syn match saseProjectSpecStatusDraft     /\%(^STATUS: \)\@<=Draft/
syn match saseProjectSpecStatusReady     /\%(^STATUS: \)\@<=Ready/
syn match saseProjectSpecStatusMailed    /\%(^STATUS: \)\@<=Mailed/
syn match saseProjectSpecStatusSubmitted /\%(^STATUS: \)\@<=Submitted/
syn match saseProjectSpecStatusReverted  /\%(^STATUS: \)\@<=Reverted/
syn match saseProjectSpecStatusArchived  /\%(^STATUS: \)\@<=Archived/
syn match saseProjectSpecStatusReserved  /\%(^STATUS: \)\@<=Reserved/

" --- PR_ORIGIN values (tri-state provenance, each gets its own color) ---
syn match saseProjectSpecOriginSase     /\%(^PR_ORIGIN: \)\@<=sase/
syn match saseProjectSpecOriginExternal /\%(^PR_ORIGIN: \)\@<=external/
syn match saseProjectSpecOriginUnknown  /\%(^PR_ORIGIN: \)\@<=unknown/

" --- PARENT value ---
syn match saseProjectSpecParentValue /\%(^PARENT: \)\@<=.\+/

" --- REFS entries (canonical artifact references) ---
syn match saseProjectSpecArtifactRef /^\s\+\zs[a-z][a-z0-9_-]*:\S\+\ze\s*$/

" --- CL / PR / BUG values (links) ---
syn match saseProjectSpecLinkValue /\%(^CL: \)\@<=.\+/
syn match saseProjectSpecLinkValue /\%(^PR: \)\@<=.\+/
syn match saseProjectSpecLinkValue /\%(^BUG: \)\@<=.\+/

" --- Test targets (Bazel-style //path/to:target) ---
syn match saseProjectSpecTestTarget /^\s\+\/\/\S\+/

" --- Test target (FAILED) annotation ---
syn match saseProjectSpecTestTargetFailed /\%(^\s\+\/\/\S\+\s\+\)\@<=(FAILED)/

" --- Entry numbers: (1), (2), (10) ---
syn match saseProjectSpecEntryNumber /^\s\+(\d\+)/

" --- Proposed entry numbers: (1a), (2b) ---
syn match saseProjectSpecProposedEntry /^\s\+(\d\+[a-z])/

" --- Entry numbers in status lines (after | pipe) ---
syn match saseProjectSpecEntryNumber /\%(|\s\+\)\@<=(\d\+)/
syn match saseProjectSpecProposedEntry /\%(|\s\+\)\@<=(\d\+[a-z])/

" --- Timestamps: [YYmmdd_HHMMSS] (HOOKS/MENTORS) ---
syn match saseProjectSpecTimestamp /\[\d\{6}_\d\{6}\]/

" --- TIMESTAMPS ISO datetime: [YYYY-MM-DD HH:MM:SS] ---
syn match saseProjectSpecTsDatetime /\[\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}:\d\{2}\]/

" --- TIMESTAMPS event type keywords (after closing bracket) ---
syn match saseProjectSpecTsCommit /\]\s\+\zsCOMMIT\>/
syn match saseProjectSpecTsStatus /\]\s\+\zsSTATUS\>/
syn match saseProjectSpecTsSync   /\]\s\+\zsSYNC\>/
syn match saseProjectSpecTsReword /\]\s\+\zsREWORD\>/

" --- Inline status words (in HOOKS / MENTORS status lines) ---
syn match saseProjectSpecInlinePassed    /\<PASSED\>/
syn match saseProjectSpecInlineFailed    /\<FAILED\>/
syn match saseProjectSpecInlineRunning   /\<RUNNING\>/
syn match saseProjectSpecInlineDead      /\<DEAD\>/
syn match saseProjectSpecInlineKilled    /\<KILLED\>/
syn match saseProjectSpecInlineStarting  /\<STARTING\>/
syn match saseProjectSpecInlineCommented /\<COMMENTED\>/

" --- Duration: (1m23s), (1h2m3s), (5m), (30s), etc. ---
syn match saseProjectSpecDuration /(\d\+h\d\+m\d\+s)/
syn match saseProjectSpecDuration /(\d\+h\d\+m)/
syn match saseProjectSpecDuration /(\d\+m\d\+s)/
syn match saseProjectSpecDuration /(\d\+[hms])/

" --- Entry reference suffixes: (2a) or (3) after " - " ---
syn match saseProjectSpecEntryRef /\%(- \)\@<=(\d\+[a-z]\?)/

" --- Suffix markers (compound prefixes before simple ones) ---
syn match saseProjectSpecSuffixPendingDead   /(?\$:[^)]*)/
syn match saseProjectSpecSuffixKilledAgent   /(\~@:[^)]*)/
syn match saseProjectSpecSuffixKilledProcess /(\~\$:[^)]*)/
syn match saseProjectSpecSuffixRejected      /(\~!:[^)]*)/
syn match saseProjectSpecSuffixError         /(!:[^)]*)/
syn match saseProjectSpecSuffixRunningAgent  /(@:[^)]*)/
syn match saseProjectSpecSuffixRunningProcess /(\$:[^)]*)/
syn match saseProjectSpecSuffixSummarize     /(%:[^)]*)/
syn match saseProjectSpecSuffixMetahook      /(\^:[^)]*)/

" --- Mentor profile:mentor in MENTORS status lines ---
" Format: | [timestamp] profile:mentor - STATUS
syn match saseProjectSpecMentorProfile /\%(|\s\+\)\@<=\%(\[\d\{6}_\d\{6}\]\s\+\)\?\zs\S\+:\S\+\ze\s\+-\s\+/

" --- Reviewer types: [critique], [review] ---
syn match saseProjectSpecReviewerType /\[\%(critique\|review\)\]/

" --- File paths (~/.sase/...) ---
syn match saseProjectSpecFilePath /\~\/\.\S\+/

" --- DELTAS entries: indent + glyph + path ---
" Glyph styling first (matches "  + ", "  ~ ", "  - " at start of line).
syn match saseProjectSpecDeltaAdded    /^\s\+\zs+\ze\s/
syn match saseProjectSpecDeltaModified /^\s\+\zs\~\ze\s/
syn match saseProjectSpecDeltaDeleted  /^\s\+\zs-\ze\s/
" The delta path: everything after the glyph on the same line.
syn match saseProjectSpecDeltaPath /\%(^\s\+[+~\-]\s\)\@<=.\+/

" --- Sub-entry file paths (after CHAT: / DIFF:) ---
syn match saseProjectSpecSubFieldPath /|\s\+\%(CHAT\|DIFF\|PLAN\):\s\+\zs\S\+/

" --- Pipe separator at start of sub-entries ---
syn match saseProjectSpecPipe /^\s\+|\s/

" --- Hook command prefixes: !, $, !$, $! ---
syn match saseProjectSpecHookPrefix /^\s\+\zs[!$]\{1,2}\ze\S/

" --- URLs ---
syn match saseProjectSpecURL /https\?:\/\/[^ )\]]\+/ contains=@NoSpell

" --- #Draft marker in MENTORS ---
syn match saseProjectSpecDraftMarker /#Draft\>/

" ==========================================================================
" Highlight Definitions (colors match sase ace TUI)
" ==========================================================================

" Field labels: bold cyan
hi def saseProjectSpecFieldLabel          guifg=#87D7FF gui=bold ctermfg=117 cterm=bold
hi def saseProjectSpecSubFieldLabel       guifg=#87D7FF gui=bold ctermfg=117 cterm=bold

" Name value: bold cyan-green
hi def saseProjectSpecNameValue           guifg=#00D7AF gui=bold ctermfg=43 cterm=bold

" Status values (bold, matching TUI)
hi def saseProjectSpecStatusWIP           guifg=#87CEEB gui=bold ctermfg=117 cterm=bold
hi def saseProjectSpecStatusDraft         guifg=#FFD700 gui=bold ctermfg=220 cterm=bold
hi def saseProjectSpecStatusReady         guifg=#87D700 gui=bold ctermfg=112 cterm=bold
hi def saseProjectSpecStatusMailed        guifg=#00D787 gui=bold ctermfg=42 cterm=bold
hi def saseProjectSpecStatusSubmitted     guifg=#00AF00 gui=bold ctermfg=34 cterm=bold
hi def saseProjectSpecStatusReverted      guifg=#808080 gui=bold ctermfg=244 cterm=bold
hi def saseProjectSpecStatusArchived      guifg=#606060 gui=bold ctermfg=240 cterm=bold
hi def saseProjectSpecStatusReserved      guifg=#AF87AF gui=bold ctermfg=139 cterm=bold

" PR_ORIGIN values (matching PR_ORIGIN_VALUE_STYLES in the TUI)
hi def saseProjectSpecOriginSase          guifg=#87D7AF gui=bold ctermfg=115 cterm=bold
hi def saseProjectSpecOriginExternal      guifg=#FF5F5F gui=bold ctermfg=203 cterm=bold
hi def saseProjectSpecOriginUnknown       guifg=#FF5F5F ctermfg=203

" Parent value: bold cyan-green
hi def saseProjectSpecParentValue         guifg=#00D7AF gui=bold ctermfg=43 cterm=bold

" Artifact references: light blue
hi def saseProjectSpecArtifactRef         guifg=#87AFFF ctermfg=111

" CL/PR/BUG links: bold underline blue
hi def saseProjectSpecLinkValue           guifg=#569CD6 gui=bold,underline ctermfg=75 cterm=bold,underline

" Test targets: bold light green
hi def saseProjectSpecTestTarget          guifg=#AFD75F gui=bold ctermfg=149 cterm=bold

" Test target (FAILED) annotation: bold red
hi def saseProjectSpecTestTargetFailed    guifg=#FF5F5F gui=bold ctermfg=203 cterm=bold

" Entry numbers: bold gold
hi def saseProjectSpecEntryNumber         guifg=#D7AF5F gui=bold ctermfg=179 cterm=bold

" Proposed entries: bold gold (same as regular entries, matching TUI)
hi def saseProjectSpecProposedEntry       guifg=#D7AF5F gui=bold ctermfg=179 cterm=bold

" Timestamps: purple (HOOKS/MENTORS old format)
hi def saseProjectSpecTimestamp           guifg=#AF87D7 ctermfg=140

" TIMESTAMPS ISO datetime: purple (matching HOOKS/MENTORS timestamps)
hi def saseProjectSpecTsDatetime          guifg=#AF87D7 ctermfg=140

" TIMESTAMPS event types (matching TUI colors)
hi def saseProjectSpecTsCommit            guifg=#00D7AF gui=bold ctermfg=43 cterm=bold
hi def saseProjectSpecTsStatus            guifg=#FFD787 gui=bold ctermfg=222 cterm=bold
hi def saseProjectSpecTsSync              guifg=#5FD7FF gui=bold ctermfg=81 cterm=bold
hi def saseProjectSpecTsReword            guifg=#D7AFFF gui=bold ctermfg=183 cterm=bold

" Inline status words
hi def saseProjectSpecInlinePassed        guifg=#00AF00 gui=bold ctermfg=34 cterm=bold
hi def saseProjectSpecInlineFailed        guifg=#FF5F5F gui=bold ctermfg=203 cterm=bold
hi def saseProjectSpecInlineRunning       guifg=#FFD700 gui=bold ctermfg=220 cterm=bold
hi def saseProjectSpecInlineDead          guifg=#B8A800 gui=bold ctermfg=142 cterm=bold
hi def saseProjectSpecInlineKilled        guifg=#FF5F5F gui=bold ctermfg=203 cterm=bold
hi def saseProjectSpecInlineStarting      guifg=#FFD700 gui=bold ctermfg=220 cterm=bold
hi def saseProjectSpecInlineCommented     guifg=#5FD7D7 gui=bold ctermfg=80 cterm=bold

" Duration: gray
hi def saseProjectSpecDuration            guifg=#808080 ctermfg=244

" Suffix badges (with background colors)
hi def saseProjectSpecSuffixError         guifg=#FFFFFF guibg=#AF0000 gui=bold ctermfg=231 ctermbg=124 cterm=bold
hi def saseProjectSpecSuffixRunningAgent  guifg=#FFFFFF guibg=#FF8C00 gui=bold ctermfg=231 ctermbg=208 cterm=bold
hi def saseProjectSpecSuffixRunningProcess guifg=#3D2B1F guibg=#FFD700 gui=bold ctermfg=234 ctermbg=220 cterm=bold
hi def saseProjectSpecSuffixKilledAgent   guifg=#FF8C00 guibg=#444444 gui=bold ctermfg=208 ctermbg=238 cterm=bold
hi def saseProjectSpecSuffixKilledProcess guifg=#B8A800 guibg=#444444 gui=bold ctermfg=142 ctermbg=238 cterm=bold
hi def saseProjectSpecSuffixRejected      guifg=#FF5F5F guibg=#444444 gui=bold ctermfg=203 ctermbg=238 cterm=bold
hi def saseProjectSpecSuffixSummarize     guifg=#FFFFFF guibg=#008B8B gui=bold ctermfg=231 ctermbg=30 cterm=bold
hi def saseProjectSpecSuffixMetahook      guifg=#FFFFFF guibg=#8B008B gui=bold ctermfg=231 ctermbg=90 cterm=bold
hi def saseProjectSpecSuffixPendingDead   guifg=#FFD700 guibg=#444444 gui=bold ctermfg=220 ctermbg=238 cterm=bold

" Entry reference suffixes: bold pink
hi def saseProjectSpecEntryRef            guifg=#FF87AF gui=bold ctermfg=211 cterm=bold

" Mentor profile:mentor - bold light blue
hi def saseProjectSpecMentorProfile       guifg=#87AFFF gui=bold ctermfg=111 cterm=bold

" Reviewer types: bold gold
hi def saseProjectSpecReviewerType        guifg=#D7AF5F gui=bold ctermfg=179 cterm=bold

" File paths: light blue
hi def saseProjectSpecFilePath            guifg=#87AFFF ctermfg=111
hi def saseProjectSpecSubFieldPath        guifg=#87AFFF ctermfg=111

" Pipe separator: gray
hi def saseProjectSpecPipe                guifg=#808080 ctermfg=244

" Hook command prefixes: bold red
hi def saseProjectSpecHookPrefix          guifg=#FF5F5F gui=bold ctermfg=203 cterm=bold

" URLs: underline blue
hi def saseProjectSpecURL                 guifg=#569CD6 gui=underline ctermfg=75 cterm=underline

" Draft marker: bold gold
hi def saseProjectSpecDraftMarker         guifg=#FFD700 gui=bold ctermfg=220 cterm=bold

" DELTAS glyphs and paths
hi def saseProjectSpecDeltaAdded          guifg=#5FD787 gui=bold ctermfg=114 cterm=bold
hi def saseProjectSpecDeltaModified       guifg=#FFD787 gui=bold ctermfg=222 cterm=bold
hi def saseProjectSpecDeltaDeleted        guifg=#FF5F5F gui=bold ctermfg=203 cterm=bold
hi def saseProjectSpecDeltaPath           guifg=#87AFFF ctermfg=111

" RUNNING entries: workspace number in cyan (no bold, matching TUI)
hi def saseProjectSpecRunningWorkspace    guifg=#5FD7FF ctermfg=81

" RUNNING pipe separators: dim
hi def saseProjectSpecRunningPipe         guifg=#808080 ctermfg=244

" PINNED marker: bold magenta/pink
hi def saseProjectSpecRunningPinned       guifg=#FF87D7 gui=bold ctermfg=212 cterm=bold

let b:current_syntax = "sase_project_spec"
