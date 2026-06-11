{:urlEncode} = require'util'
html2unicode = require 'html'
lfs = require'lfs'

hex_to_char = (x) ->
  string.char(tonumber(x, 16))

unescape = (url) ->
  url\gsub("%%(%x%x)", hex_to_char)

html_escape = (s) ->
  s = s\gsub('&', '&amp;')
  s = s\gsub('<', '&lt;')
  s = s\gsub('>', '&gt;')
  s = s\gsub('"', '&quot;')
  return s

-- All URLs in this module is under this prefix
urlbase = '/image/'

safe = (fn) ->
  f, ext = fn\match'^(.*)%.(.-)$'
  f = f\gsub '[^%w%-]', ''
  return f..'.'..ext

video_html = (video, ch) ->
  videourl = ivar2.config.webserverprefix..urlbase..'file/'..video
  escaped_ch = html_escape ch
  [[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Video - ]]..escaped_ch..[[</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  background: #141010;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  font-family: system-ui, -apple-system, sans-serif;
}
video {
  width: 100%;
  max-height: calc(100vh - 60px);
  object-fit: contain;
  background: #000;
}
.controls {
  display: flex;
  gap: 8px;
  padding: 12px;
  width: 100%;
  justify-content: center;
}
.controls button {
  background: #680747;
  color: #fff;
  border: none;
  border-radius: 6px;
  padding: 8px 16px;
  font-size: 14px;
  cursor: pointer;
  transition: background 0.2s;
}
.controls button:hover {
  background: #c3195d;
}
</style>
</head>
<body>
<video id="v" src="]]..videourl..[[" controls autoplay loop>
Your browser does not support the video element.
<a href="]]..videourl..[[">Download video</a>
</video>
<div class="controls">
<button onclick="rotate(90)">⟳ Rotate CW</button>
<button onclick="rotate(-90)">⟲ Rotate CCW</button>
</div>
<script>
var deg = 0;
function rotate(d) {
  deg += d;
  document.getElementById('v').style.transform = 'rotate(' + deg + 'deg)';
}
</script>
</body>
</html>
]]


ivar2.webserver.regUrl "#{urlbase}(.*)$", (req, res) =>
  url = req.url
  send = (body, code, content_type) ->
    if not code then code = "200"
    if not content_type then content_type = 'text/html'
    res\append ':status', code
    res\append 'Content-Type', content_type
    res\append 'Content-Length', tostring(#body)
    req\write_headers(res, false, 30)
    req\write_body_from_string(body, 30)
    return

  file = url\match '/file/(.*)$'
  if file
    fn = "cache/images/#{safe file}"
    size = lfs.attributes(fn).size
    content_type = 'image/jpeg'
    if file\lower!\match '.png'
      content_type = 'image/png'
    if file\lower!\match '.heif'
      content_type = 'image/heif'
    if file\lower!\match '.heic'
      content_type = 'image/heic'
    if file\lower!\match '.svg'
      content_type = 'image/svg+xml'
    if file\lower!\match '.mp4'
      content_type = 'video/mp4'
    if file\lower!\match '.mkv'
      content_type = 'video/x-matroska'
    if file\lower!\match '.mov'
      content_type = 'video/quicktime'
    if file\lower!\match '.mp3'
      content_type = 'audio/mpeg'

    res\append ':status', '200'
    res\append 'Content-Type', content_type
    res\append 'Content-Length', tostring(size)
    req\write_headers(res, false, 30)
    fd = io.open(fn, 'rb')
    req\write_body_from_file(fd, 5*60)
    fd\close!
    return

  -- Serve video player page
  video = url\match '/video/(.*)$'
  if video then
    channel_raw = url\match('channel=(.+)%s*') or ''
    send video_html(video, channel_raw)
    return

  channel = url\match('channel=(.+)%s*')
  unless channel
    send 'Invalid channel', 404
    return

  channel = html2unicode channel
  unescaped_channel = unescape channel
  escaped_channel = html_escape unescaped_channel

  html = [[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="IRCSNAP ]]..escaped_channel..[[">
<meta name="theme-color" content="#680747">
<title>IRCSNAP ]]..escaped_channel..[[</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --pink: #f70776;
  --magenta: #c3195d;
  --purple: #680747;
  --dark: #141010;
  --bg: #1a1515;
  --card: #221c1c;
  --text: #e8e0e0;
  --muted: #9a8e8e;
  --border: #3a3232;
}

html { height: 100%; }

body {
  font-family: system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif;
  background: var(--bg);
  color: var(--text);
  min-height: 100%;
  display: flex;
  flex-direction: column;
}

header {
  background: var(--purple);
  padding: 16px 20px;
  text-align: center;
  box-shadow: 0 2px 8px rgba(0,0,0,0.3);
}
header h1 {
  font-size: 18px;
  font-weight: 600;
  color: #fff;
  letter-spacing: 0.5px;
}

.main {
  flex: 1;
  max-width: 520px;
  width: 100%;
  margin: 0 auto;
  padding: 20px 16px;
}

.card {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 18px;
  margin-bottom: 16px;
}

.card h2 {
  font-size: 14px;
  text-transform: uppercase;
  letter-spacing: 1px;
  color: var(--muted);
  margin-bottom: 12px;
}

label.field {
  display: block;
  margin-bottom: 12px;
}
label.field span {
  display: block;
  font-size: 12px;
  color: var(--muted);
  margin-bottom: 4px;
}
label.field input {
  width: 100%;
  padding: 10px 12px;
  border: 1px solid var(--border);
  border-radius: 6px;
  background: var(--dark);
  color: var(--text);
  font-size: 15px;
  outline: none;
  transition: border-color 0.2s;
}
label.field input:focus {
  border-color: var(--pink);
}

.btn-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}

.btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  padding: 12px 10px;
  border: none;
  border-radius: 8px;
  background: var(--pink);
  color: #fff;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.2s, transform 0.1s;
  text-decoration: none;
}
.btn:hover { background: var(--magenta); }
.btn:active { transform: scale(0.97); }
.btn .icon { font-size: 20px; }

#preview-area {
  display: none;
  text-align: center;
}
#preview-area img, #preview-area video {
  max-width: 100%;
  max-height: 240px;
  border-radius: 8px;
  margin: 10px 0;
}
#preview-name {
  font-size: 13px;
  color: var(--muted);
  margin-bottom: 6px;
}
#confirm-btn {
  display: inline-block;
  margin-top: 6px;
  padding: 10px 24px;
}
#cancel-btn {
  display: inline-block;
  margin-top: 6px;
  margin-left: 8px;
  background: var(--border);
}
#cancel-btn:hover { background: #4a4242; }

#status {
  display: none;
  text-align: center;
  padding: 12px 0;
}
#status p { font-size: 14px; margin-bottom: 6px; }
.progress-track {
  height: 4px;
  background: var(--border);
  border-radius: 2px;
  overflow: hidden;
}
.progress-bar {
  height: 100%;
  width: 0%;
  background: var(--pink);
  transition: width 0.15s;
}

.dropzone {
  border: 2px dashed var(--border);
  border-radius: 10px;
  padding: 28px 16px;
  text-align: center;
  transition: border-color 0.2s, background 0.2s;
  cursor: pointer;
}
.dropzone.dragover {
  border-color: var(--pink);
  background: rgba(247, 7, 118, 0.06);
}
.dropzone p {
  color: var(--muted);
  font-size: 14px;
}
.dropzone .dz-icon {
  font-size: 32px;
  margin-bottom: 6px;
}

footer {
  background: var(--dark);
  border-top: 1px solid var(--border);
  padding: 20px 16px;
  text-align: center;
}
footer p {
  font-size: 13px;
  color: var(--muted);
  margin: 4px 0;
}
footer a { color: var(--pink); text-decoration: none; }
footer a:hover { text-decoration: underline; }
footer strong { color: var(--text); }

.hidden { display: none !important; }
</style>
</head>
<body>

<header>
  <h1>Share to IRC — ]]..escaped_channel..[[</h1>
</header>

<div class="main">

  <div class="card">
    <label class="field">
      <span>Nickname</span>
      <input id="sender" type="text" placeholder="Your nick">
    </label>
    <label class="field">
      <span>Message (optional)</span>
      <input id="text" type="text" placeholder="Say something...">
    </label>
  </div>

  <div class="card" id="upload-card">
    <h2>Choose media</h2>
    <div class="btn-grid" id="buttons">
      <label for="capturei" class="btn"><span class="icon">&#128247;</span> Snap photo</label>
      <input type="file" accept="image/*" id="capturei" capture="camera" class="hidden">

      <label for="capturef" class="btn"><span class="icon">&#128193;</span> Browse files</label>
      <input type="file" accept="image/*,image/heif,image/heic" id="capturef" class="hidden">

      <label for="capturev" class="btn"><span class="icon">&#127909;</span> Record video</label>
      <input type="file" accept="video/*" id="capturev" capture="camcorder" class="hidden">

      <label for="capturevf" class="btn"><span class="icon">&#128192;</span> Upload video</label>
      <input type="file" accept="video/*" id="capturevf" class="hidden">
    </div>

    <div id="preview-area">
      <p id="preview-name"></p>
      <div id="preview-media"></div>
      <button id="confirm-btn" class="btn">Upload</button>
      <button id="cancel-btn" class="btn">Cancel</button>
    </div>

    <div id="status">
      <p id="uploadprogress">Uploading...</p>
      <div class="progress-track"><div id="bar" class="progress-bar"></div></div>
    </div>
  </div>

  <div class="card">
    <h2>Drag &amp; drop / paste</h2>
    <div class="dropzone" id="dropzone">
      <div class="dz-icon">&#128219;</div>
      <p>Drop files here or paste an image</p>
      <input type="file" id="box__dropi" class="hidden" multiple>
    </div>
  </div>

</div>

<footer>
  <p><strong>What is this?</strong></p>
  <p>Share to IRC is a simple web app for sharing media directly from your device to an IRC channel.</p>
  <p>Use your browser menu to add this to your home screen for quick access.</p>
  <p>Made by <a href="//github.com/torhve/">xt</a></p>
</footer>

<script>
var uploading = false;
var pendingFile = null;
var uploadSize = 0;

function encode(str) {
  return decodeURIComponent(encodeURIComponent(str));
}

function showPreview(file) {
  pendingFile = file;
  document.getElementById('buttons').style.display = 'none';
  document.getElementById('preview-area').style.display = 'block';
  document.getElementById('preview-name').textContent = file.name + ' (' + (file.size / 1024).toFixed(1) + ' KB)';
  var container = document.getElementById('preview-media');
  container.innerHTML = '';
  if (file.type.indexOf('image') === 0) {
    var img = document.createElement('img');
    var reader = new FileReader();
    reader.onload = function(e) { img.src = e.target.result; };
    reader.readAsDataURL(file);
    container.appendChild(img);
  } else if (file.type.indexOf('video') === 0) {
    var vid = document.createElement('video');
    vid.src = URL.createObjectURL(file);
    vid.controls = true;
    vid.style.maxHeight = '240px';
    container.appendChild(vid);
  }
}

function hidePreview() {
  pendingFile = null;
  document.getElementById('preview-area').style.display = 'none';
  document.getElementById('preview-media').innerHTML = '';
  document.getElementById('buttons').style.display = 'grid';
}

function startUpload(file) {
  if (uploading) {
    alert('Already uploading, please wait.');
    return;
  }
  if (!file) file = pendingFile;
  if (!file) return;
  uploading = true;
  hidePreview();
  document.getElementById('buttons').style.display = 'none';
  document.getElementById('status').style.display = 'block';

  var xhr = new XMLHttpRequest();
  xhr.upload.onprogress = function(e) {
    var pct = e.lengthComputable
      ? Math.floor(e.loaded * 100 / e.total)
      : Math.floor(e.loaded * 100 / uploadSize);
    document.getElementById('bar').style.width = pct + '%';
    document.getElementById('uploadprogress').textContent = 'Uploading... ' + pct + '%';
  };
  xhr.onload = function() {
    document.getElementById('uploadprogress').textContent = 'Upload complete, shared to IRC!';
    uploading = false;
    document.getElementById('buttons').style.display = 'grid';
    document.getElementById('status').style.display = 'none';
  };
  xhr.onerror = function() {
    document.getElementById('uploadprogress').textContent = 'Upload failed.';
    uploading = false;
    document.getElementById('buttons').style.display = 'grid';
    document.getElementById('status').style.display = 'none';
  };
  xhr.onabort = function() {
    document.getElementById('uploadprogress').textContent = 'Upload canceled.';
    uploading = false;
    document.getElementById('buttons').style.display = 'grid';
    document.getElementById('status').style.display = 'none';
  };

  xhr.open('POST', 'upload/?channel=]]..channel..[[', true);
  var reader = new FileReader();
  reader.readAsArrayBuffer(file);
  xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
  xhr.setRequestHeader('X-Filename', encode(file.name));
  xhr.setRequestHeader('X-Text', encode(document.getElementById('text').value));
  xhr.setRequestHeader('X-Sender', encode(document.getElementById('sender').value));
  reader.onload = function(e) {
    uploadSize = e.total;
    xhr.send(e.target.result);
  };
}

// Button file inputs
['capturei', 'capturef', 'capturev', 'capturevf'].forEach(function(id) {
  document.getElementById(id).addEventListener('change', function(e) {
    var file = e.target.files[0];
    if (file) showPreview(file);
  });
});

// Confirm / cancel
document.getElementById('confirm-btn').addEventListener('click', function() {
  startUpload(pendingFile);
});
document.getElementById('cancel-btn').addEventListener('click', function() {
  hidePreview();
});

// Nick persistence
(function() {
  var stored = localStorage.getItem('sender');
  if (stored) document.getElementById('sender').value = stored;
  document.getElementById('sender').addEventListener('change', function(e) {
    localStorage.setItem('sender', e.target.value);
  });
})();

// Drag & drop
(function() {
  var dz = document.getElementById('dropzone');
  dz.addEventListener('dragover', function(e) {
    e.preventDefault();
    dz.classList.add('dragover');
  });
  dz.addEventListener('dragleave', function() {
    dz.classList.remove('dragover');
  });
  dz.addEventListener('drop', function(e) {
    e.preventDefault();
    dz.classList.remove('dragover');
    var file = e.dataTransfer.files[0];
    if (file) showPreview(file);
  });
  dz.addEventListener('click', function() {
    document.getElementById('box__dropi').click();
  });
  document.getElementById('box__dropi').addEventListener('change', function(e) {
    var file = e.target.files[0];
    if (file) showPreview(file);
  });
})();

// Paste
document.addEventListener('paste', function(e) {
  var item = e.clipboardData.items[0];
  if (item && item.type.indexOf('image') === 0) {
    var blob = item.getAsFile();
    if (blob) showPreview(blob);
  }
});
</script>

</body>
</html>
]]
  if req.method == 'POST'
    fn = req.headers['x-filename']
    sender = req.headers['x-sender'] or ''
    text = req.headers['x-text'] or ''
    file = req.filename
    ivar2\Log 'info', "imageupload: Recieved file name: <#{fn}> datalen: #{#file}, sender: <#{sender}> text: <#{text}>, channel: <#{unescaped_channel}>"
    if fn and file
      html = 'Ok'
      realfn = "#{os.time!}-#{safe fn}"
      save = ->
        os.rename req.filename, "cache/images/#{realfn}"
        if sender ~= ''
          sender = "<#{sender\sub(1, 100)}> "
        if text ~= ''
          text = text\sub(1, 100) .. ' '
        file_or_video = 'file'
        if realfn\match '%.mp4$'
          file_or_video = 'video'
        if realfn\match '%.mov$'
          file_or_video = 'video'
        msg = "[IRCSNAP] #{sender}#{text}#{ivar2.config.webserverprefix}#{urlbase}#{file_or_video}/#{realfn}"
        ivar2\Privmsg unescaped_channel, msg
      ok, err = pcall(save)
      unless ok
        ivar2\Log 'error', "imageupload: Error during saving upload: %s", err
    else
      html = 'Not OK'

  send html


lfs.mkdir('cache/images')

PRIVMSG:
  '^%pircsnap$': (source, destination) =>
    channel = urlEncode destination
    say "#{ivar2.config.webserverprefix}#{urlbase}?channel=#{channel} IRCSNAP - sharing is caring."