/*
 * Admin push UI: start/cancel + progress pie
 */
(function($){
  let polling = null;
  function drawPie(pct){
    const c = document.getElementById('buzzsaw-pie');
    if(!c) return;
    const ctx = c.getContext('2d');
    const r = c.width/2, cx = r, cy = r;
    ctx.clearRect(0,0,c.width,c.height);
    ctx.beginPath(); ctx.arc(cx,cy,r-4,0,2*Math.PI); ctx.lineWidth = 8; ctx.strokeStyle = '#e1e5ea'; ctx.stroke();
    const end = (pct/100)*2*Math.PI;
    ctx.beginPath(); ctx.arc(cx,cy,r-4,-Math.PI/2, end - Math.PI/2); ctx.lineWidth = 8; ctx.strokeStyle = '#2271b1'; ctx.stroke();
    $('#buzzsaw-pct').text(Math.floor(pct)+'%');
  }
  function poll(){
    $.ajax({
      url: BUZZSAW.rest + '/progress',
      method: 'GET',
      beforeSend: xhr => xhr.setRequestHeader('X-WP-Nonce', BUZZSAW.nonce)
    }).done(st => {
      const total = st.total||0, done = st.done||0;
      const pct = total ? (done/total*100) : 0;
      drawPie(pct);
      $('#buzzsaw-status').text(st.last || 'Working…');
      if (!st.running) stopPolling();
    });
  }
  function startPolling(){ if (!polling) polling = setInterval(poll, 1500); }
  function stopPolling(){ if (polling) { clearInterval(polling); polling = null; poll(); } }
  $(document).on('click', '#buzzsaw-start', function(){
    $('#buzzsaw-status').text('Queuing…');
    $.ajax({
      url: BUZZSAW.rest + '/start',
      method: 'POST',
      beforeSend: xhr => xhr.setRequestHeader('X-WP-Nonce', BUZZSAW.nonce)
    }).done(() => {
      $('#buzzsaw-cancel').show();
      startPolling(); poll();
    }).fail(xhr => {
      alert('Start failed: ' + (xhr.responseJSON && xhr.responseJSON.message ? xhr.responseJSON.message : 'Unknown error'));
    });
  });
  $(document).on('click', '#buzzsaw-cancel', function(){
    $.ajax({
      url: BUZZSAW.rest + '/cancel',
      method: 'POST',
      beforeSend: xhr => xhr.setRequestHeader('X-WP-Nonce', BUZZSAW.nonce)
    }).done(() => {
      stopPolling();
      $('#buzzsaw-status').text('Canceled');
      $('#buzzsaw-cancel').hide();
    });
  });
  $(function(){ drawPie(0); poll(); });
})(jQuery);
