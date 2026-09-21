export const money=(value:number)=>new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'}).format(value||0)
export const dateTime=(value:string)=>new Intl.DateTimeFormat('pt-BR',{dateStyle:'short',timeStyle:'short'}).format(new Date(value))
export const time=(value:string)=>new Intl.DateTimeFormat('pt-BR',{hour:'2-digit',minute:'2-digit'}).format(new Date(value))
export const localDayRange=(offset=0)=>{const start=new Date();start.setDate(start.getDate()+offset);start.setHours(0,0,0,0);const end=new Date(start);end.setDate(end.getDate()+1);return[start.toISOString(),end.toISOString()] as const}
export const periodRange=(period:'today'|'week'|'month')=>{const end=new Date();const start=new Date();start.setHours(0,0,0,0);if(period==='week')start.setDate(start.getDate()-6);if(period==='month')start.setDate(1);return[start.toISOString(),end.toISOString()] as const}
export const paymentLabel=(value:'pix'|'cash'|'card')=>value==='pix'?'PIX':value==='cash'?'Dinheiro':'Cartão'
