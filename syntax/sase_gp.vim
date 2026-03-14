" Vim syntax file
" Language:    SASE Project Spec (.gp)
" Maintainer:  Bryan Bugyi

if exists("b:current_syntax")
  finish
endif

syn case match

" ==========================================================================
" Syntax Groups
" ==========================================================================

" --- Field Labels (column 0) ---
syn match saseGpFieldLabel /^NAME:/
syn match saseGpFieldLabel /^DESCRIPTION:/
syn match saseGpFieldLabel /^STATUS:/
syn match saseGpFieldLabel /^PARENT:/
syn match saseGpFieldLabel /^CL:/
syn match saseGpFieldLabel /^PR:/
syn match saseGpFieldLabel /^BUG:/
syn match saseGpFieldLabel /^TEST TARGETS:/
syn match saseGpFieldLabel /^KICKSTART:/
syn match saseGpFieldLabel /^COMMITS:/
syn match saseGpFieldLabel /^HOOKS:/
syn match saseGpFieldLabel /^COMMENTS:/
syn match saseGpFieldLabel /^MENTORS:/
syn match saseGpFieldLabel /^RUNNING:/
syn match saseGpFieldLabel /^WORKSPACE_DIR:/

" --- WORKSPACE_DIR value ---
syn match saseGpFilePath /\%(^WORKSPACE_DIR: \)\@<=.\+/

" --- RUNNING entries: #N | PID | workflow | cl_name | timestamp ---
syn match saseGpRunningWorkspace /^\s\+#\d\+/
syn match saseGpRunningPipe /\s|\s/
syn match saseGpRunningPinned /\<PINNED\>/

" --- Sub-entry field labels (| CHAT: , | DIFF:) ---
syn match saseGpSubFieldLabel /|\s\+\zs\%(CHAT\|DIFF\):/

" --- NAME value ---
syn match saseGpNameValue /\%(^NAME: \)\@<=.\+/

" --- STATUS values (each gets its own color) ---
syn match saseGpStatusWIP       /\%(^STATUS: \)\@<=WIP/
syn match saseGpStatusDraft     /\%(^STATUS: \)\@<=Draft/
syn match saseGpStatusReady     /\%(^STATUS: \)\@<=Ready/
syn match saseGpStatusMailed    /\%(^STATUS: \)\@<=Mailed/
syn match saseGpStatusSubmitted /\%(^STATUS: \)\@<=Submitted/
syn match saseGpStatusReverted  /\%(^STATUS: \)\@<=Reverted/
syn match saseGpStatusArchived  /\%(^STATUS: \)\@<=Archived/

" --- PARENT value ---
syn match saseGpParentValue /\%(^PARENT: \)\@<=.\+/

" --- CL / PR / BUG values (links) ---
syn match saseGpLinkValue /\%(^CL: \)\@<=.\+/
syn match saseGpLinkValue /\%(^PR: \)\@<=.\+/
syn match saseGpLinkValue /\%(^BUG: \)\@<=.\+/

" --- Test targets (Bazel-style //path/to:target) ---
syn match saseGpTestTarget /^\s\+\/\/\S\+/

" --- Entry numbers: (1), (2), (10) ---
syn match saseGpEntryNumber /^\s\+(\d\+)/

" --- Proposed entry numbers: (1a), (2b) ---
syn match saseGpProposedEntry /^\s\+(\d\+[a-z])/

" --- Timestamps: [YYmmdd_HHMMSS] ---
syn match saseGpTimestamp /\[\d\{6}_\d\{6}\]/

" --- Inline status words (in HOOKS / MENTORS status lines) ---
syn match saseGpInlinePassed   /\<PASSED\>/
syn match saseGpInlineFailed   /\<FAILED\>/
syn match saseGpInlineRunning  /\<RUNNING\>/
syn match saseGpInlineDead     /\<DEAD\>/
syn match saseGpInlineKilled   /\<KILLED\>/
syn match saseGpInlineStarting /\<STARTING\>/

" --- Duration: (1m23s) ---
syn match saseGpDuration /(\d\+m\d\+s)/

" --- Suffix markers (compound prefixes before simple ones) ---
syn match saseGpSuffixPendingDead   /(?\$:[^)]*)/
syn match saseGpSuffixKilledAgent   /(\~@:[^)]*)/
syn match saseGpSuffixKilledProcess /(\~\$:[^)]*)/
syn match saseGpSuffixRejected      /(\~!:[^)]*)/
syn match saseGpSuffixError         /(!:[^)]*)/
syn match saseGpSuffixRunningAgent  /(@:[^)]*)/
syn match saseGpSuffixRunningProcess /(\$:[^)]*)/
syn match saseGpSuffixSummarize     /(%:[^)]*)/
syn match saseGpSuffixMetahook      /(\^:[^)]*)/

" --- Reviewer types: [critique], [review] ---
syn match saseGpReviewerType /\[\%(critique\|review\)\]/

" --- File paths (~/.sase/...) ---
syn match saseGpFilePath /\~\/\.\S\+/

" --- Sub-entry file paths (after CHAT: / DIFF:) ---
syn match saseGpSubFieldPath /|\s\+\%(CHAT\|DIFF\):\s\+\zs\S\+/

" --- Pipe separator at start of sub-entries ---
syn match saseGpPipe /^\s\+|\s/

" --- Hook command prefixes: !, $, !$, $! ---
syn match saseGpHookPrefix /^\s\+\zs[!$]\{1,2}\ze\S/

" --- URLs ---
syn match saseGpURL /https\?:\/\/[^ )\]]\+/ contains=@NoSpell

" --- #Draft marker in MENTORS ---
syn match saseGpDraftMarker /#Draft\>/

" ==========================================================================
" Highlight Definitions (colors match sase ace TUI)
" ==========================================================================

" Field labels: bold cyan
hi def saseGpFieldLabel          guifg=#87D7FF gui=bold ctermfg=117 cterm=bold
hi def saseGpSubFieldLabel       guifg=#87D7FF gui=bold ctermfg=117 cterm=bold

" Name value: bold cyan-green
hi def saseGpNameValue           guifg=#00D7AF gui=bold ctermfg=43 cterm=bold

" Status values
hi def saseGpStatusWIP           guifg=#87CEEB ctermfg=117
hi def saseGpStatusDraft         guifg=#FFD700 ctermfg=220
hi def saseGpStatusReady         guifg=#87D700 ctermfg=112
hi def saseGpStatusMailed        guifg=#00D787 ctermfg=42
hi def saseGpStatusSubmitted     guifg=#00AF00 ctermfg=34
hi def saseGpStatusReverted      guifg=#808080 ctermfg=244
hi def saseGpStatusArchived      guifg=#606060 ctermfg=240

" Parent value: cyan-green
hi def saseGpParentValue         guifg=#00D7AF ctermfg=43

" CL/PR/BUG links: bold underline blue
hi def saseGpLinkValue           guifg=#569CD6 gui=bold,underline ctermfg=75 cterm=bold,underline

" Test targets: light green
hi def saseGpTestTarget          guifg=#AFD75F ctermfg=149

" Entry numbers: bold gold
hi def saseGpEntryNumber         guifg=#D7AF5F gui=bold ctermfg=179 cterm=bold

" Proposed entries: bold pink
hi def saseGpProposedEntry       guifg=#FF87AF gui=bold ctermfg=211 cterm=bold

" Timestamps: purple
hi def saseGpTimestamp           guifg=#AF87D7 ctermfg=140

" Inline status words
hi def saseGpInlinePassed        guifg=#00AF00 gui=bold ctermfg=34 cterm=bold
hi def saseGpInlineFailed        guifg=#FF5F5F gui=bold ctermfg=203 cterm=bold
hi def saseGpInlineRunning       guifg=#FFD700 gui=bold ctermfg=220 cterm=bold
hi def saseGpInlineDead          guifg=#B8A800 gui=bold ctermfg=142 cterm=bold
hi def saseGpInlineKilled        guifg=#FF5F5F gui=bold ctermfg=203 cterm=bold
hi def saseGpInlineStarting      guifg=#FFD700 gui=bold ctermfg=220 cterm=bold

" Duration: gray
hi def saseGpDuration            guifg=#808080 ctermfg=244

" Suffix badges (with background colors)
hi def saseGpSuffixError         guifg=#FFFFFF guibg=#AF0000 gui=bold ctermfg=231 ctermbg=124 cterm=bold
hi def saseGpSuffixRunningAgent  guifg=#FFFFFF guibg=#FF8C00 gui=bold ctermfg=231 ctermbg=208 cterm=bold
hi def saseGpSuffixRunningProcess guifg=#3D2B1F guibg=#FFD700 gui=bold ctermfg=234 ctermbg=220 cterm=bold
hi def saseGpSuffixKilledAgent   guifg=#FF8C00 guibg=#444444 gui=bold ctermfg=208 ctermbg=238 cterm=bold
hi def saseGpSuffixKilledProcess guifg=#B8A800 guibg=#444444 gui=bold ctermfg=142 ctermbg=238 cterm=bold
hi def saseGpSuffixRejected      guifg=#FF5F5F guibg=#444444 gui=bold ctermfg=203 ctermbg=238 cterm=bold
hi def saseGpSuffixSummarize     guifg=#FFFFFF guibg=#008B8B gui=bold ctermfg=231 ctermbg=30 cterm=bold
hi def saseGpSuffixMetahook      guifg=#FFFFFF guibg=#8B008B gui=bold ctermfg=231 ctermbg=90 cterm=bold
hi def saseGpSuffixPendingDead   guifg=#FFD700 guibg=#444444 gui=bold ctermfg=220 ctermbg=238 cterm=bold

" Reviewer types: bold gold
hi def saseGpReviewerType        guifg=#D7AF5F gui=bold ctermfg=179 cterm=bold

" File paths: light blue
hi def saseGpFilePath            guifg=#87AFFF ctermfg=111
hi def saseGpSubFieldPath        guifg=#87AFFF ctermfg=111

" Pipe separator: gray
hi def saseGpPipe                guifg=#808080 ctermfg=244

" Hook command prefixes: bold red
hi def saseGpHookPrefix          guifg=#FF5F5F gui=bold ctermfg=203 cterm=bold

" URLs: underline blue
hi def saseGpURL                 guifg=#569CD6 gui=underline ctermfg=75 cterm=underline

" Draft marker: bold gold
hi def saseGpDraftMarker         guifg=#FFD700 gui=bold ctermfg=220 cterm=bold

" RUNNING entries: workspace number in cyan
hi def saseGpRunningWorkspace    guifg=#5FD7FF gui=bold ctermfg=81 cterm=bold

" RUNNING pipe separators: dim
hi def saseGpRunningPipe         guifg=#808080 ctermfg=244

" PINNED marker: bold magenta/pink
hi def saseGpRunningPinned       guifg=#FF87D7 gui=bold ctermfg=212 cterm=bold

let b:current_syntax = "sase_gp"
