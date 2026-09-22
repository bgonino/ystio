type InstallPromptEvent=Event&{prompt:()=>Promise<void>;userChoice:Promise<{outcome:'accepted'|'dismissed'}>};
let pending:InstallPromptEvent|null=null;
if(typeof window!=='undefined')window.addEventListener('beforeinstallprompt',event=>{event.preventDefault();pending=event as InstallPromptEvent;window.dispatchEvent(new Event('pwa-install-ready'))});
export const canInstall=()=>pending!==null;
export async function installPwa(){if(!pending)return false;await pending.prompt();const result=await pending.userChoice;if(result.outcome==='accepted')pending=null;return result.outcome==='accepted'}
