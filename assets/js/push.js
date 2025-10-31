/*
 * Admin push UI: start/cancel + progress pie
 */
(function($){
  let polling=null;

  function drawPie(pct){
    const c=document.getElementById('buzzsaw-pie'); if(!c) return;
    const ctx=c.getContext('2d'); const r=c.width/2, cx=r, cy=r;
    ctx.clearRect(0,0,c.width,c.height);
    ctx.beginPath(); ctx.arc(cx,cy,r-4,0,2*Math.PI); ctx.lineWidth=8; ctx.strokeStyle='#e1e5ea'; ctx.stroke();
    const end=(pct/100)*2*Math.PI;
    ctx.beginPath(); ctx.arc(cx,cy,r-4,-Math.PI/2,end-Math.PI/2); ctx.lineWidth=8; ctx.strokeStyle='#2271b1'; ctx.stroke();
    $('#buzzsaw-pct').text(Math.floor(pct)+'%');
  }

  function setStatus(msg){ $('#buzzsaw-status').text(msg||''); }

  function poll(){
    $.ajax({
      url: BUZZSAW.rest+'/progress', method:'GET',
      beforeSend:x=>x.setRequestHeader('X-WP-Nonce', BUZZSAW.nonce)
    }).done(st=>{
      const total=st.total||0, done=st.done||0, pct=total?(done/total*100):0;
      drawPie(pct); setStatus(st.last||'Working…');
      if(!st.running){ stopPolling(); $('#buzzsaw-start').prop('disabled',false); $('#buzzsaw-cancel').hide(); }
    });
  }

  function startPolling(){ if(!polling) polling=setInterval(poll,1500); }
  function stopPolling(){ if(polling){ clearInterval(polling); polling=null; } }

  $(document).on('click','#buzzsaw-start',function(){
    // Reset UI to 0% immediately
    drawPie(0); setStatus('Starting…');
    $('#buzzsaw-start').prop('disabled',true); $('#buzzsaw-cancel').show();

    $.ajax({
      url: BUZZSAW.rest+'/start', method:'POST',
      beforeSend:x=>x.setRequestHeader('X-WP-Nonce', BUZZSAW.nonce)
    }).done(()=>{ startPolling(); poll(); })
      .fail(xhr=>{
        alert('Start failed: '+(xhr.responseJSON&&xhr.responseJSON.message?xhr.responseJSON.message:'Unknown error'));
        $('#buzzsaw-start').prop('disabled',false); $('#buzzsaw-cancel').hide(); setStatus('Idle'); drawPie(0);
      });
  });

  $(document).on('click','#buzzsaw-cancel',function(){
    $.ajax({
      url: BUZZSAW.rest+'/cancel', method:'POST',
      beforeSend:x=>x.setRequestHeader('X-WP-Nonce', BUZZSAW.nonce)
    }).done(()=>{ stopPolling(); setStatus('Canceled'); $('#buzzsaw-start').prop('disabled',false); $('#buzzsaw-cancel').hide(); });
  });

  $(function(){ drawPie(0); setStatus('Idle'); poll(); });
})(jQuery);
