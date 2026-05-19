using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;

byte[] AES_KEY = { 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54, 0x32, 0x10 };
const int AES_BLOCK = 0x10;
const int SLOT_SIZE = 0x060030;
const int USER_DATA_SIZE = 0x060020;
const int HEADER_SIZE = 0x02C0;
const int IGT_OFFSET = 0x1C;
const int NAME1_OFFSET = 0x108;
const int NAME2_OFFSET = 0x18C;
const int NAME_MAX_BYTES = 64;

int slot = 0;
string path = "/home/user/.steam/steam/steamapps/compatdata/570940/pfx/drive_c/users/steamuser/My Documents/NBGI/DARK SOULS REMASTERED/84341421/DRAKS0005.sl2";

// Number of ciphertext bytes needed to cover the name field (rounded to block boundary)
int partialDecryptLen = ((NAME1_OFFSET + NAME_MAX_BYTES + AES_BLOCK - 1) / AES_BLOCK) * AES_BLOCK;

// ---- Helpers ----

byte[] DecryptBytes(byte[] cipher, byte[] iv)
{
    using var aes = Aes.Create();
    aes.Key = AES_KEY;
    aes.IV = iv;
    aes.Mode = CipherMode.CBC;
    aes.Padding = PaddingMode.None;
    using var ms = new MemoryStream();
    using var cs = new CryptoStream(ms, aes.CreateDecryptor(), CryptoStreamMode.Write);
    cs.Write(cipher);
    cs.FlushFinalBlock();
    return ms.ToArray();
}

byte[] EncryptBytes(byte[] plain, byte[] iv)
{
    using var aes = Aes.Create();
    aes.Key = AES_KEY;
    aes.IV = iv;
    aes.Mode = CipherMode.CBC;
    aes.Padding = PaddingMode.None;
    using var ms = new MemoryStream();
    using var cs = new CryptoStream(ms, aes.CreateEncryptor(), CryptoStreamMode.Write);
    cs.Write(plain);
    cs.FlushFinalBlock();
    return ms.ToArray();
}

string FormatIgt(int ms)
{
    var t = TimeSpan.FromMilliseconds(ms);
    return $"{(int)t.TotalHours:D2}:{t.Minutes:D2}:{t.Seconds:D2}.{t.Milliseconds:D3}";
}

string ReadName(byte[] plain, int offset)
{
    int len = 0;
    for (int i = 0; i < NAME_MAX_BYTES - 1; i += 2)
    {
        if (plain[offset + i] == 0 && plain[offset + i + 1] == 0) { len = i; break; }
    }
    return Encoding.Unicode.GetString(plain, offset, len);
}

void WriteName(byte[] data, int offset, string value)
{
    byte[] encoded = Encoding.Unicode.GetBytes(value);
    int writeLen = Math.Min(encoded.Length, NAME_MAX_BYTES - 2);
    Array.Copy(encoded, 0, data, offset, writeLen);
    Array.Fill<byte>(data, 0, offset + writeLen, NAME_MAX_BYTES - writeLen);
}

// ---- Actions ----

void Read()
{
    byte[] iv = new byte[AES_BLOCK];
    byte[] cipher = new byte[partialDecryptLen];
    using (var f = new FileStream(path, FileMode.Open, FileAccess.Read))
    {
        f.Seek(HEADER_SIZE + slot * SLOT_SIZE, SeekOrigin.Begin);
        f.ReadExactly(iv);
        f.ReadExactly(cipher);
    }

    byte[] plain = DecryptBytes(cipher, iv);
    Console.WriteLine($"Name: {ReadName(plain, NAME1_OFFSET)}");
    Console.WriteLine($"IGT:  {FormatIgt(BitConverter.ToInt32(plain, IGT_OFFSET))}");
}

void Write(string newName, int? newIgtMs)
{
    byte[] save = File.ReadAllBytes(path);
    int slotOffset = HEADER_SIZE + slot * SLOT_SIZE;

    byte[] iv = save[slotOffset..(slotOffset + AES_BLOCK)];
    byte[] cipher = save[(slotOffset + AES_BLOCK)..(slotOffset + AES_BLOCK + USER_DATA_SIZE)];
    byte[] plain = DecryptBytes(cipher, iv);

    WriteName(plain, NAME1_OFFSET, newName);
    WriteName(plain, NAME2_OFFSET, newName);
    if (newIgtMs.HasValue)
        BitConverter.TryWriteBytes(plain.AsSpan(IGT_OFFSET), newIgtMs.Value);

    byte[] newCipher = EncryptBytes(plain, iv);
    byte[] md5 = MD5.HashData(newCipher);

    // MD5 of ciphertext replaces the IV slot (matches game's save format)
    md5.CopyTo(save, slotOffset);
    newCipher.CopyTo(save, slotOffset + AES_BLOCK);
    File.WriteAllBytes(path, save);
    Console.WriteLine("Written.");
}

// IGT-only read using two-block CBC chaining trick (no need for the real IV)
int GetIgtFast()
{
    byte[] buf = new byte[AES_BLOCK * 2];
    using (var f = new FileStream(path, FileMode.Open, FileAccess.Read))
    {
        f.Seek(HEADER_SIZE + slot * SLOT_SIZE + AES_BLOCK, SeekOrigin.Begin);
        f.ReadExactly(buf);
    }
    // Use C[0] as IV to decrypt C[1], giving P[1] which contains IGT at byte 0xC
    return BitConverter.ToInt32(DecryptBytes(buf[AES_BLOCK..], buf[..AES_BLOCK]), 0xC);
}

void Benchmark()
{
    const int ITERATIONS = 1000;
    GetIgtFast(); // warmup
    var sw = Stopwatch.StartNew();
    for (int i = 0; i < ITERATIONS; i++)
        GetIgtFast();
    sw.Stop();
    Console.WriteLine($"GetIgt: {sw.ElapsedMilliseconds}ms total, {sw.Elapsed.TotalMicroseconds / ITERATIONS:F1}µs/iter");
}

// ---- Dispatch ----

switch (args.ElementAtOrDefault(0))
{
    case "read":
        Read();
        break;
    case "write":
        if (args.Length < 2) { Console.Error.WriteLine("Usage: write <name> [igt_ms]"); break; }
        int? igtMs = args.Length >= 3 ? int.Parse(args[2]) : null;
        Write(args[1], igtMs);
        break;
    case "benchmark":
        Benchmark();
        break;
    default:
        Console.Error.WriteLine("Actions: read | write <name> [igt_ms] | benchmark");
        break;
}
