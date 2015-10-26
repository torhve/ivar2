{:simplehttp, :json, :urlEncode} = require'util'
html2unicode = require 'html'
nixio = require'nixio'
fs = require'nixio.fs'
ltn12 = require'ltn12'

-- All URLs in this module is under this prefix
urlbase = '/image/'

safe = (fn) ->
  f, ext = fn\match'^(.*)%.(.-)$'
  f = f\gsub '[^%w%-]', ''
  return f..'.'..ext

video_html = (video) ->
  videourl = ivar2.config.webserverprefix..urlbase..'file/'..video
  [[
  <!DOCTYPE html>
  <html>
  <head>
  <meta charset="utf-8">
  <style type="text/css">
    video {
      width: 100%;
      height: auto !important;
    }
    button {
    padding: 20px;
      box-shadow: 0px 2px 2px 0px rgba(0, 0, 0, 0.14), 0px 3px 1px -2px rgba(0, 0, 0, 0.2), 0px 1px 5px 0px rgba(0, 0, 0, 0.12);
      border: medium none;
      border-radius: 2px;
      color: #000;
      position: relative;
      height: 36px;
      min-width: 64px;
      padding: 0px 8px;
      display: block;
      font-weight: 500;
      text-transform: uppercase;
      letter-spacing: 0px;
      overflow: hidden;
      will-change: box-shadow, transform;
      transition: box-shadow 0.2s cubic-bezier(0.4, 0, 1, 1) 0s, background-color 0.2s cubic-bezier(0.4, 0, 0.2, 1) 0s, color 0.2s cubic-bezier(0.4, 0, 0.2, 1) 0s;
      outline: medium none;
      margin: 5px;
      cursor: pointer;
      text-decoration: none;
      text-align: center;
      line-height: 36px;
      vertical-align: middle;
      border-collapse: collapse;
      border-spacing: 0px;
      background-color: #E6B85C;
    }
  </style>
  <body>
    <video id="v" src="]]..videourl..[[" controls autoplay loop>
      Your browser does not support the <code>video</code> element.
      Try the direct link to the video: <a href="]]..videourl..[[">video</a>
    </video>
    <script>
    function rotate(deg) {
      console.log(deg);
      var prop = 'transform';
      document.getElementById('v').style[prop]='rotate('+deg+'deg)';

    }
    </script>
    <button onclick="rotate(90)">Rotate ⟳</button>
    <button onclick="rotate(-90)">Rotate ⟲</button>

  </body>
  </html>
  ]]


ivar2.webserver.regUrl "#{urlbase}(.*)$", (req, res) ->
  send = (body, code, content_type) ->
    if not code then code = 200
    if not content_type then content_type = 'text/html'
    res\set_status code
    res\set_header 'Content-Type', content_type
    res\set_header 'Content-Length', #body
    res\set_body body
    res\send!
    res.on_error = (res, req, err) ->
      ivar2\Log 'error', 'imageupload: error: %s', err

  file = req.url\match '/file/(.*)$'
  if file
    fn = "cache/images/#{safe file}"
    size = nixio.fs.stat(fn).size
    fd = ltn12.source.file(io.open fn, 'rb')
    --body = fd\read '*a'
    --fd\close!
    content_type = 'image/jpeg'
    if file\match '.png'
      content_type = 'image/png'
    if file\match '.svg'
      content_type = 'image/svg'
    if file\match '.mp4'
      content_type = 'video/mp4'
    if file\match '.mp3'
      content_type = 'audio/mp3'

    res\set_status code
    res\set_header 'Content-Type', content_type
    res\set_header 'Content-Length', size
    res\set_body fd
    res\send!
    ivar2\Log 'error', 'imageupload: serving: %s', fn
    return

  -- Serve video player page
  video = req.url\match '/video/(.*)$'
  if video then
    return send video_html(video)

  channel = req.url\match('channel=(.+)%s*')
  unless channel
    send 'Invalid channel', 404
    return

  channel = html2unicode channel
  unescaped_channel = channel\gsub '%%23', '#'

  html = [[
  <!DOCTYPE html>
  <html>
  <head>

  <!-- ivar2 photo uploader -->
  <meta charset="utf-8">
  <meta http-equiv="X-UA-Compatible" content="IE=Edge">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="IRCSNAP ]]..unescaped_channel..[[">
  <meta name="theme-color" content="#8f4099">

  <title>IRCSNAP</title>

  <style type="text/css">
  html { height: 100% }
  body {
    height: 100%;
    margin: 0;
    font-family: "Roboto","Segoe UI","Arial",sans-serif !important;
    background-color: #FAFAFA;
    font-size: 14px;
    font-weight: 400;
    line-height: 20px;
    color: rgba(0, 0, 0, 0.87);
    display: flex;
    flex-direction: column;
    overflow-y: auto;
    overflow-x: hidden;
    position: relative;
    max-width: 768px;
    padding-left: 5px;
    padding-right: 5px;
  }
  #buttons, #status, .content {
    display: flex;
    flex-flow: column wrap;
    margin: 0px auto;
    width: 100%;
    align-items: stretch;
    margin-bottom: 30px;
  }
  h3 {
    background-color: #8f4099;
    color: white;
    padding: 20px;
    margin-top: 0;
    margin-left: -20px;
    margin-right: -20px;
  }
  .group            {
    position:relative;
    margin-bottom:45px;
  }
  .group input               {
    font-size:18px;
    padding:10px 10px 10px 5px;
    display:block;
    width:99%;
    border:none;
    border-bottom:1px solid #757575;
  }
  input:focus         { outline:none; }

  /* LABEL ======================================= */
  .group label {
    color:#999;
    font-size:18px;
    font-weight:normal;
    position:absolute;
    pointer-events:none;
    left:5px;
    top:10px;
    transition:0.2s ease all;
    -moz-transition:0.2s ease all;
    -webkit-transition:0.2s ease all;
  }

  /* active state */
  .group input:focus ~ label, .group input:valid ~ label        {
    top:-20px;
    font-size:14px;
    color:#5264AE;
  }

  /* BOTTOM BARS ================================= */
  .bar    { position:relative; display:block; width:99%; }
  .bar:before, .bar:after     {
    content:'';
    height:2px;
    width:0;
    bottom:1px;
    position:absolute;
    background:#5264AE;
    transition:0.2s ease all;
    -moz-transition:0.2s ease all;
    -webkit-transition:0.2s ease all;
  }
  .bar:before {
    left:50%;
  }
  .bar:after {
    right:50%;
  }

  /* active state */
  input:focus ~ .bar:before, input:focus ~ .bar:after {
    width:50%;
  }

  /* HIGHLIGHTER ================================== */
  .highlight {
    position:absolute;
    height:60%;
    width:100%;
    top:25%;
    left:0;
    pointer-events:none;
    opacity:0.5;
  }

  /* active state */
  input:focus ~ .highlight {
    -webkit-animation:inputHighlighter 0.3s ease;
    -moz-animation:inputHighlighter 0.3s ease;
    animation:inputHighlighter 0.3s ease;
  }

  /* ANIMATIONS ================ */
  @-webkit-keyframes inputHighlighter {
      from { background:#5264AE; }
    to    { width:0; background:transparent; }
  }
  @-moz-keyframes inputHighlighter {
      from { background:#5264AE; }
    to    { width:0; background:transparent; }
  }
  @keyframes inputHighlighter {
      from { background:#5264AE; }
    to    { width:0; background:transparent; }
  }

  .pictake {
    padding: 20px;
    box-shadow: 0px 2px 2px 0px rgba(0, 0, 0, 0.14), 0px 3px 1px -2px rgba(0, 0, 0, 0.2), 0px 1px 5px 0px rgba(0, 0, 0, 0.12);
    border: medium none;
    border-radius: 2px;
    color: #000;
    position: relative;
    height: 36px;
    min-width: 64px;
    padding: 0px 8px;
    display: inline-block;
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0px;
    overflow: hidden;
    will-change: box-shadow, transform;
    transition: box-shadow 0.2s cubic-bezier(0.4, 0, 1, 1) 0s, background-color 0.2s cubic-bezier(0.4, 0, 0.2, 1) 0s, color 0.2s cubic-bezier(0.4, 0, 0.2, 1) 0s;
    outline: medium none;
    cursor: pointer;
    text-decoration: none;
    text-align: center;
    line-height: 36px;
    vertical-align: middle;
    border-collapse: collapse;
    border-spacing: 0px;
    background-color: #E6B85C;
  }
    .pictake .icon {
      font-size: 2em;
    }
  #progress {
    display: block;
    height: 3px;
    background-color: #b0d0ef;
  }
  #bar {
    display: block;
    height: 3px;
    background-color: #3a81f0;
    width: 0%;
  }

  </style>
  <body>
  <div class="content">
  <h3>Share to IRC app - ]]..unescaped_channel..[[ edition</h3>
    <p>Fill in your nick/name and optional text and then click on one of the yellow buttons to attach image. It will appear instantly on IRC!</p>
    <form>
      <div class="group">
        <input id="sender" type="text" required>
        <span class="highlight"></span>
        <span class="bar"></span>
        <label>Your name</label>
      </div>
      <div class="group">
        <input id="text" type="text" required>
        <span class="highlight"></span>
        <span class="bar"></span>
        <label>Attach text</label>
      </div>
    </form>

    <div style="display: none;" id="status">
      <p id="uploadprogress">Uploading. Percent complete: 0 %</p>
      <div id="progress"><div id="bar"></div></div>
    </div>
    <div id="buttons">
      <label for="capturei" class="pictake" data-click="onClickTake('capturei')"><span class="icon">📷</span> Snap picture!</label> <input type="file" accept="image/*" id="capturei" capture="camera" style="visibility:hidden;">
      <label for="capturef" class="pictake" data-click="onClickTake('capturef')"><span class="icon">📂</span> Browse gallery!</label> <input type="file" accept="image/*" id="capturef" style="visibility:hidden;">
      <label for="capturev" class="pictake" data-click="onClickTake('capturev')"><span class="icon">🎥</span> Capture video!</label> <input type="file" accept="video/*" capture="camcorder" id="capturev" style="visibility:hidden;">
      <label for="capturevf" class="pictake" data-click="onClickTake('capturevf')"><span class="icon">🎥</span> Upload video!</label> <input type="file" accept="video/*" id="capturevf" style="visibility:hidden;">
    </div>
    <!--
    <p>Share audio: <input type="file" accept="audio/*" id="capturea" capture="microphone">
    -->
    <div class="footer">
      <p>
        <strong>What is this?</strong>
      </p>
      <p>Share to IRC is a simple web app for sharing media directly from your device to an IRC channel.</p>
      <p>Click Tools -&gt;  Add to homescreen to create a convenient shortcut for easy and fast access to sharing</p>
    </div>
  </div>
  <script>

  // Global lock for uploading or not
  var uploading = false;
  // Store file size of upload to compute progress;
  var uploadsize = 0;

  function uploadingTransition() {
    uploading = true;
    document.getElementById('buttons').style.display = 'none';
    document.getElementById('status').style.display = 'flex';
  }

  function uploadedTransition(success) {
    uploading = false;
    /*
    if(success) {
      document.getElementById('status').style.display = 'none';
    }*/
    document.getElementById('buttons').style.display = 'flex';
  }

  function onClickTake(id) {
    document.getElementById(id).click();
  }

  // progress on transfers from the server to the client (downloads)
  function updateProgress (oEvent) {
    var percentComplete;
    if (oEvent.lengthComputable) {
      percentComplete = Math.floor(oEvent.loaded*100 / oEvent.total);
      // ...
    } else {
      percentComplete = Math.floor(oEvent.loaded*100 / uploadsize);
    }
    document.getElementById('bar').style.width = percentComplete + '%';
    document.getElementById('uploadprogress').textContent = "Uploading. Percent complete: " + percentComplete + ' %';
  }

  function transferComplete(evt) {
    console.log("The transfer is complete.");
    document.getElementById('uploadprogress').textContent = "Upload complete, shared to IRC!"
    uploadedTransition(true);
  }

  function transferFailed(evt) {
    var msg = "An error occurred while transferring the file."
    document.getElementById('uploadprogress').textContent = msg;
    console.log(msg);
    uploadedTransition(false);
  }

  function transferCanceled(evt) {
    var msg = "The transfer has been canceled by the user.";
    document.getElementById('uploadprogress').textContent = msg;
    console.log(msg);
    uploadedTransition(false);
  }

  function javascript_is_nice(str) {
    return unescape(encodeURIComponent(str));
  }

  function sendMedia(el) {
    if(uploading) {
      alert('Already uploading, please wait.');
      return;
    }
    uploadingTransition();
    var target = el.target;
    var file = target.files[0];
    var xhr = new XMLHttpRequest();
    xhr.addEventListener("progress", updateProgress);
    xhr.addEventListener("load", transferComplete);
    xhr.addEventListener("error", transferFailed);
    xhr.addEventListener("abort", transferCanceled);
    xhr.upload.onprogress = updateProgress;
    var text = document.getElementById('text').value;
    var sender = document.getElementById('sender').value;
    xhr.open('POST', 'upload/?channel=]]..channel..[[', true);
    var reader = new FileReader();
    reader.readAsArrayBuffer(file);
    xhr.setRequestHeader("X-Requested-With", "XMLHttpRequest");
    xhr.setRequestHeader("X-Filename", javascript_is_nice(file.name));
    xhr.setRequestHeader("X-Text", javascript_is_nice(text));
    xhr.setRequestHeader("X-Sender", javascript_is_nice(sender));
    xhr.setRequestHeader("Transfer-Encoding", "chunked");
    reader.onload = function(e) {
      uploadsize = e.total;
      xhr.send(e.target.result);
    };

  }
  function storeName(e) {
    var target = e.target;
    localStorage.setItem('sender', target.value);
  }
  document.getElementById('capturei').addEventListener('change', sendMedia, false);
  document.getElementById('capturef').addEventListener('change', sendMedia, false);
  document.getElementById('capturev').addEventListener('change', sendMedia, false);
  document.getElementById('capturevf').addEventListener('change', sendMedia, false);
  // document.getElementById('capturea').addEventListener('change', sendMedia, false);


  var name = document.getElementById('sender').value;
  if(name == '') {
    var stored = localStorage.getItem('sender');
    if (stored != null) {
      document.getElementById('sender').value = stored;
    }
  }

  document.getElementById('sender').addEventListener('change', storeName, false);
  </script>
  </body>
  </html>
  ]]
  if req.method == 'POST'
    fn = req.headers['X-Filename']
    sender = req.headers['X-Sender'] or ''
    text = req.headers['X-Text'] or ''
    file = req.filename
    ivar2\Log 'info', "imageupload: Recieved file name: <#{fn}> datalen: #{#file}, sender: <#{sender}> text: <#{text}>, channel: <#{unescaped_channel}>"
    if fn and file
      html = 'Ok'
      realfn = "#{os.time!}-#{safe fn}"
      save = ->
        --fd = nixio.open "cache/images/#{realfn}", 'w+', 0400
        --written = fd\write file
        --fd\sync!
        --fd\close!
        -- Move tempfile to real location
        fs.move req.filename, "cache/images/#{realfn}"
        if sender ~= ''
          sender = "<#{sender\sub(1, 100)}> "
        if text ~= ''
          text = text\sub(1, 100) .. ' '
        file_or_video = 'file'
        if realfn\match '%.mp4$'
          file_or_video = 'video'
        msg = "[IRCSNAP] #{sender}#{text}#{ivar2.config.webserverprefix}#{urlbase}#{file_or_video}/#{realfn}"
        ivar2\Privmsg unescaped_channel, msg
      ok, err = pcall(save)
      unless ok
        ivar2\Log 'error', "imageupload: Error during saving upload: %s", err
    else
      html = 'Not OK'

  send html


-- Attempt to create the cache folder.
nixio.fs.mkdir('cache/images')

PRIVMSG:
  '^%pircsnap$': (source, destination) =>
    channel = urlEncode destination
    say "#{ivar2.config.webserverprefix}#{urlbase}?channel=#{channel} IRCSNAP - sharing is caring."


