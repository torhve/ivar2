local html2unicode = require 'html'

-- HTML-to-text extractor using iterative position-based removal.
-- Lua's .- is NOT truly non-greedy: <script>.-</script> matches from the FIRST
-- opening tag to the LAST closing tag, consuming all intermediate content.
-- Position-based scanning avoids this entirely.

-- Remove one occurrence of a block tag (case-insensitive), replacing with delimiter.
-- Returns modified string, or original if no match found.
local function remove_one_block(html, open_tag, close_tag, replacement)
    local pos = 1
    while pos <= #html do
        local start = html:find(open_tag, pos, true)  -- plain text search
        if not start then
            return html
        end
        -- Find matching close tag after the opening tag
        local after_open = start + #open_tag
        local end_pos = html:find(close_tag, after_open, true)
        if end_pos then
            html = html:sub(1, start - 1) .. replacement .. html:sub(end_pos + #close_tag)
            return html
        end
        -- No matching close tag found; skip past this opening tag
        pos = start + 1
    end
    return html
end

-- Iteratively remove all occurrences of a block type.
local function remove_all_blocks(html, open_tag, close_tag, replacement)
    local prev
    repeat
        prev = html
        html = remove_one_block(prev, open_tag, close_tag, replacement)
    until html == prev
    return html
end

local function extract_fallback(html, opts)
    local max_length = opts.max_length or 0
    local min_chunk = opts.min_chunk_size or 15

    -- Remove script blocks iteratively (handles multiple blocks and embedded < chars)
    html = remove_all_blocks(html, '<script', '</script>', '\n')
    html = remove_all_blocks(html, '<SCRIPT', '</SCRIPT>', '\n')
    html = remove_all_blocks(html, '<Script', '</Script>', '\n')

    -- Remove style blocks iteratively
    html = remove_all_blocks(html, '<style', '</style>', '\n')
    html = remove_all_blocks(html, '<STYLE', '</STYLE>', '\n')
    html = remove_all_blocks(html, '<Style', '</Style>', '\n')

    -- Remove HTML comments (iterative for multiple comments)
    html = remove_all_blocks(html, '<!--', '-->', '\n')

    -- Remove DOCTYPE (regex is fine - only one per page)
    html = html:gsub('<!DOCTYPE[^>]*>', '', 1)

    -- Remove processing instructions
    html = html:gsub('<?[^?]*?>', '')

    -- Remove all remaining tags, replacing with delimiter
    html = html:gsub('<[^>]*>', '\n')

    -- Decode entities
    html = html2unicode(html)

    -- Split on newlines to get text chunks (preserves original tag-delimited boundaries)
    local chunks = {}
    for segment in html:gmatch('([^\n]+)') do
        segment = segment:gsub('[\r\t]+', ' ')
            :gsub('%s+', ' ')
            :gsub('^%s+', '')
            :gsub('%s+$', '')
        if #segment >= min_chunk then
            chunks[#chunks + 1] = segment
        end
    end

    -- Sort descending by length (longest content first)
    table.sort(chunks, function(a, b) return #a > #b end)

    -- Assemble up to max_length
    local result = {}
    local total = 0
    for _, chunk in ipairs(chunks) do
        if max_length > 0 and total + #chunk + 1 > max_length then
            break
        end
        result[#result + 1] = chunk
        total = total + #chunk + 1
    end

    return table.concat(result, '. ')
end

return {
    extract = function(html, opts)
        opts = opts or {}

        if not html or #html == 0 then
            return ''
        end

        return extract_fallback(html, opts)
    end,
}
