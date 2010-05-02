function toggleCheck() {
  $$('#host_select_form input.host_select_boxes').each(function(box){
                                                                box.checked=!box.checked;
                                                                //if (box.checked == true ) { box.checked = false; }
                                                                //if (box.checked == false) { box.checked = true;  }
                                                                insertHostVal(box);
                                                                });
  return false;
}
function insertHostVal(cbox) {
  //alert(cbox.value)
  //if (cbox.checked){
  //    alert(cbox.value)
  //hosts
  var request = new Ajax.Request('hosts/save_checkbox', {
                method: 'get',
                parameters: { box: cbox.value, is_checked: cbox.checked },
                onSuccess: function(res){
                   return false;
                },
                onFailure: function(res){
                   alert("Something failed! Select the checkbox again.")
                   return false;
                }
              });
}

function clearSession() {
  var request = new Ajax.Request('update_multiple', {
                method: 'post',
                parameters: { resetSession: "true" },
                onSuccess: function(res){
                   return false;
                },
                onFailure: function(res){
                   alert("Something failed! Click the button again.")
                   return false;
                }
              });
}
