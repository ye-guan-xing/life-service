export interface Service {
  id: number
  name: string
  merchant_name: string
  price: number
  category: string
  image_url?: string
  stock?: number
}

export interface Order {
  id: number
  service_id: number
  service_name: string
  merchant_name: string
  price: number
  user_name: string
  user_phone: string
  status: number
  create_time: string
  create_time_formatted?: string
}
