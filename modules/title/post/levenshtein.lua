local function levenshtein_distance(str1, str2)
    local len1, len2 = #str1, #str2
    local char1, char2, distance = {}, {}, {}
    str1:gsub('.', function (c) table.insert(char1, c) end)
    str2:gsub('.', function (c) table.insert(char2, c) end)
    for i = 0, len1 do distance[i] = {} end
    for i = 0, len1 do distance[i][0] = i end
    for i = 0, len2 do distance[0][i] = i end
    for i = 1, len1 do
        for j = 1, len2 do
            distance[i][j] = math.min(
                distance[i-1][j  ] + 1,
                distance[i  ][j-1] + 1,
                distance[i-1][j-1] + (char1[i] == char2[j] and 0 or 1)
                )
        end
    end
    return distance[len1][len2]
end

local function urlstrip(str)
	str = str:gsub('^https?://.-/', '')
	return str
end

local function strclean(str)
	str = str:lower()
	str = urlstrip(str)
	str = str:gsub('www', '')
	str = str:gsub('%.com', '')
	str = str:gsub('[/%-_ ]', ' ')
	return str
end

function levratio(str1, str2)
	str1 = strclean(str1)
	str2 = strclean(str2)
	local maxlen = math.max(#str1, #str2)
	local distance = levenshtein_distance( str1, str2 )
    return distance/maxlen

end

do
    return function(source, destination, queue)
    -- Check levenshtein_distance between URL and title. It's just spammy to print title when it is already in the URL itself.
        local cutoff = ivar2.config.titleLevenshteinDistanceRatio or 0.8
        if not queue.output or queue.output == '' then
            return
        end
        local ratio = levratio(queue.url, queue.output)
        ivar2:Log('debug', 'title/post/levenshtein: %s', ratio)
        if (ratio < cutoff) then
            queue.output = false
        end
    end
end

