local htmltext = require 'htmltext'

describe('htmltext module', function()
    describe('extract', function()
        it('strips script blocks', function()
            local result = htmltext.extract('<p>Hello</p><script>alert(1)</script>', {min_chunk_size = 1})
            assert.is_not_nil(result:find('Hello'))
            assert.is_nil(result:find('alert'))
        end)

        it('strips style blocks', function()
            local result = htmltext.extract('<style>.foo{color:red}</style><p>Visible</p>', {min_chunk_size = 1})
            assert.is_not_nil(result:find('Visible'))
            assert.is_nil(result:find('color'))
        end)

        it('strips HTML comments', function()
            local result = htmltext.extract('Before<!-- hidden -->After', {min_chunk_size = 1})
            assert.is_not_nil(result:find('Before'))
            assert.is_not_nil(result:find('After'))
            assert.is_nil(result:find('hidden'))
        end)

        it('strips regular tags, keeps text', function()
            local result = htmltext.extract('<div><b>Bold</b></div>', {min_chunk_size = 1})
            assert.is_not_nil(result:find('Bold'))
            assert.is_nil(result:find('<'))
        end)

        it('decodes HTML entities', function()
            local result = htmltext.extract('<p>&amp;&nbsp;&lt;</p>', {min_chunk_size = 1})
            assert.is_not_nil(result:find('&'))
            assert.is_nil(result:find('&amp;'))
        end)

        it('filters chunks below min_chunk_size', function()
            local html = '<span>Hi</span>'
                .. '<p>This is a longer paragraph of text</p>'
            local result = htmltext.extract(html, {min_chunk_size = 20})
            assert.is_nil(result:find('Hi'))
            assert.is_not_nil(result:find('longer'))
        end)

        it('truncates to max_length', function()
            local result = htmltext.extract(
                '<p>This is the first long paragraph with lots of words</p>' ..
                '<p>This is the second long paragraph with even more words here</p>',
                {max_length = 50, min_chunk_size = 1}
            )
            assert.is_true(#result <= 50)
        end)

        it('returns longest chunks first', function()
            local result = htmltext.extract(
                '<p>Short</p><p>This is a much longer paragraph of content</p>',
                {min_chunk_size = 1}
            )
            local pos_short = result:find('Short')
            local pos_long = result:find('much longer')
            assert.is_true(pos_long < pos_short)
        end)

        it('handles empty input', function()
            assert.are_equal('', htmltext.extract(nil))
            assert.are_equal('', htmltext.extract(''))
        end)

        it('handles tags-only input', function()
            assert.are_equal('', htmltext.extract('<br><hr>'))
        end)

        it('handles real-world page structure', function()
            local page = [[<html><head><title>Test</title></head><body>
<nav>Menu Home About Contact</nav>
<article><p>Main article content here with important information
about the topic being discussed at length.</p></article>
<footer>Copyright 2024 All rights reserved</footer>
<script>var x=1;alert(x)</script>
<style>body{margin:0}</style>
</body></html>]]
            local result = htmltext.extract(page, {max_length = 200, min_chunk_size = 15})
            assert.is_not_nil(result:find('Main article'))
            assert.is_nil(result:find('alert'))
            assert.is_nil(result:find('margin'))
        end)

        it('handles attributes with > inside quotes', function()
            local result = htmltext.extract(
                '<a title="x>y">Click here for more info about this thing</a>',
                {max_length = 100, min_chunk_size = 3}
            )
            assert.is_not_nil(result:find('Click here'))
            assert.is_nil(result:find('<'))
        end)

        it('concatenates chunks with period separator', function()
            local result = htmltext.extract(
                '<p>First paragraph here</p><p>Second paragraph here</p>',
                {min_chunk_size = 1}
            )
            assert.is_not_nil(result:find('%. '))
            assert.is_not_nil(result:find('First'))
            assert.is_not_nil(result:find('Second'))
        end)

        it('strips DOCTYPE declarations', function()
            local page = [[<!DOCTYPE html><html><head><title>Page</title></head><body><p>Content here</p></body></html>]]
            local result = htmltext.extract(page, {min_chunk_size = 1})
            assert.is_nil(result:find('DOCTYPE'))
            assert.is_not_nil(result:find('Content'))
        end)

        it('strips XML processing instructions', function()
            local page = [[<?xml version="1.0" encoding="UTF-8"?><root><item>Text content</item></root>]]
            local result = htmltext.extract(page, {min_chunk_size = 1})
            assert.is_nil(result:find('version'))
            assert.is_not_nil(result:find('Text content'))
        end)

        it('handles script with embedded < characters', function()
            local result = htmltext.extract('<p>Before</p><script>if(x<y){alert("ok")}</script><p>After</p>', {min_chunk_size = 1})
            assert.is_not_nil(result:find('Before'))
            assert.is_not_nil(result:find('After'))
            assert.is_nil(result:find('alert'))
        end)

        it('handles mixed-case SCRIPT and STYLE tags', function()
            local page = '<SCRIPT>alert(1)</SCRIPT><style>.x{y:z}</style><p>Visible text here</p>'
            local result = htmltext.extract(page, {min_chunk_size = 1})
            assert.is_nil(result:find('alert'))
            assert.is_nil(result:find('y:z'))
            assert.is_not_nil(result:find('Visible'))
        end)

        it('handles script with > inside attributes', function()
            local result = htmltext.extract('<script src="a>b">alert(1)</script><p>Good content here</p>', {min_chunk_size = 1})
            assert.is_nil(result:find('alert'))
            assert.is_not_nil(result:find('Good content'))
        end)

        it('handles deeply nested structure', function()
            local page = [[<div><section><article><header><h1>Title</h1></header><p>Body paragraph with meaningful text for extraction.</p></article></section></div>]]
            local result = htmltext.extract(page, {min_chunk_size = 5})
            assert.is_not_nil(result:find('Body paragraph'))
            assert.is_nil(result:find('<'))
        end)
    end)
end)
