export function Ring({
  size,
  progress,
  color,
  label,
  fontSize,
}: {
  size: number;
  progress: number;
  color: string;
  label: string;
  fontSize?: number;
}) {
  const radius = 42;
  const circumference = 2 * Math.PI * radius;
  return (
    <div className="ring" style={{ width: size, height: size }}>
      <svg viewBox="0 0 100 100">
        <circle
          cx="50"
          cy="50"
          r={radius}
          fill="none"
          stroke={color}
          strokeOpacity={0.2}
          strokeWidth={8}
        />
        <circle
          cx="50"
          cy="50"
          r={radius}
          fill="none"
          stroke={color}
          strokeWidth={8}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={circumference * (1 - progress)}
        />
      </svg>
      <b style={{ fontSize: fontSize ?? size * 0.32 }}>{label}</b>
    </div>
  );
}
