export interface TcpSocketPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}
