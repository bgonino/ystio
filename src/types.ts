export type PaymentMethod='pix'|'cash'; export type SaleStatus='completed'|'cancelled';
export interface Product{id:string;user_id:string;name:string;description:string|null;unit_cost:number;sale_price:number;current_stock:number;minimum_stock:number|null;active:boolean;created_at:string;updated_at:string}
export interface SaleItem{id:string;sale_id:string;product_id:string;product_name:string;quantity:number;unit_price:number;unit_cost:number;subtotal:number}
export interface Sale{id:string;user_id:string;calculated_total:number;received_amount:number;payment_method:PaymentMethod;status:SaleStatus;created_at:string;cancelled_at:string|null;sale_items?:SaleItem[]}
export interface InventoryMovement{id:string;user_id:string;product_id:string;movement_type:'entry'|'sale_out'|'positive_adjustment'|'negative_adjustment'|'sale_cancellation';quantity:number;unit_cost:number|null;reference_type:string|null;reference_id:string|null;notes:string|null;created_at:string;products?:{name:string}}
export interface DashboardStats{revenue:number;cost:number;grossProfit:number;salesCount:number;units:number;pix:number;cash:number;averageTicket:number}
