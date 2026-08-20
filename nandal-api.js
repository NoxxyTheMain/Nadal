const nandal = window.supabase.createClient(window.NANDAL_CONFIG.url, window.NANDAL_CONFIG.publishableKey);
window.NANDAL_API = {
  client: nandal,
  async uploadPhoto(file, position) { const { data:{ user } }=await nandal.auth.getUser(); if(!user)throw Error('Sign in required'); if(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>5242880)throw Error('Use a JPG, PNG, or WebP image under 5 MB.'); const path=`${user.id}/${crypto.randomUUID()}.${file.name.split('.').pop()}`; let r=await nandal.storage.from('profile-photos').upload(path,file);if(r.error)throw r.error;r=await nandal.from('photos').insert({owner_id:user.id,storage_path:path,position});if(r.error)throw r.error;return path; },
  async deletePhoto(photoId, storagePath) { const { data:{ user } }=await nandal.auth.getUser(); if(!user)throw Error('Sign in required'); let r=await nandal.storage.from('profile-photos').remove([storagePath]); if(r.error)throw r.error; r=await nandal.from('photos').delete().eq('id',photoId).eq('owner_id',user.id); if(r.error)throw r.error; },
  async reorderPhotos(orderedIds) { for(let i=0;i<orderedIds.length;i++){const r=await nandal.from('photos').update({position:i+100}).eq('id',orderedIds[i]);if(r.error)throw r.error} for(let i=0;i<orderedIds.length;i++){const r=await nandal.from('photos').update({position:i}).eq('id',orderedIds[i]);if(r.error)throw r.error} },
  async swipe(target, choice) { const {data,error}=await nandal.rpc('record_swipe',{target,choice});if(error)throw error;return data; },
  async sendMessage(match_id, body) { const {data:{user}}=await nandal.auth.getUser();const {error}=await nandal.from('messages').insert({match_id,sender_id:user.id,body});if(error)throw error; },
  async block(blocked_id) { const {data:{user}}=await nandal.auth.getUser();const {error}=await nandal.from('blocks').insert({blocker_id:user.id,blocked_id});if(error)throw error; },
  async report(reported_id, reason, details='') { const {data:{user}}=await nandal.auth.getUser();const {error}=await nandal.from('reports').insert({reporter_id:user.id,reported_id,reason,details});if(error)throw error; },
  async deleteAccount(note='') { const {error}=await nandal.rpc('delete_own_account',{note});if(error)throw error; },
  async resolveReport(report_id, new_status, note='') { const {error}=await nandal.rpc('moderator_resolve_report',{target_report:report_id,new_status,note});if(error)throw error; },
  async hideProfile(target_profile, note='') { const {error}=await nandal.rpc('moderator_set_discoverable',{target_profile,discoverable:false,note});if(error)throw error; },
  async restoreProfile(target_profile, note='') { const {error}=await nandal.rpc('moderator_set_discoverable',{target_profile,discoverable:true,note});if(error)throw error; }
};
