package com.hailiang.family.circle;

import com.alibaba.fastjson.JSON;
import com.alibaba.fastjson.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * 支持断点续传的客户端上传测试代码
 * 对应服务端 FileUploadHandler
 */
public class FileUploadClient {

    private static final String SERVER_HOST = "192.168.2.104";
    private static final int SERVER_PORT = 10087;
    private static final int CHUNK_SIZE = 8 * 1024; // 8KB chunks
    
    // 协议常量
    private static final byte[] MAGIC = { (byte) 0xFA, (byte) 0xCE }; // 魔数常量，两个字节
    private static final int HEADER_LENGTH = 8; // 帧头总长度
    // 文件断点续传使用到的帧类型
    private static final byte META_FRAME = 0x01;
    private static final byte DATA_FRAME = 0x02;
    private static final byte END_FRAME = 0x03;
    private static final byte ACK_FRAME = 0x04;
    private static final byte RESUME_CHECK = 0x05;
    private static final byte RESUME_ACK = 0x06;

    public static void main(String[] args) {
        // TODO: 修改为实际文件路径
        String filePath = "/Users/debugcode/Documents/java/idea/duyao/我的老婆/老婆性感丝袜美腿美臀.MOV";
        File file = new File(filePath);
        
        if (!file.exists()) {
            System.err.println("文件不存在: " + filePath);
            return;
        }

        try {
            System.out.println("开始处理文件: " + file.getName());
            uploadFile(file);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public static void uploadFile(File file) throws Exception {
        // 1. 计算文件 MD5
        System.out.print("正在计算MD5...");
        String md5 = calculateMD5(file);
        System.out.println(" 完成. MD5: " + md5);

        try (SocketChannel channel = SocketChannel.open()) {
            channel.connect(new InetSocketAddress(SERVER_HOST, SERVER_PORT));
            channel.configureBlocking(true);
            System.out.println("成功连接服务器: " + SERVER_HOST + ":" + SERVER_PORT);

            // 2. 发送断点检查帧
            long offset = 0;
            String taskId = null;
            
            JSONObject resumeInfo = checkResume(channel, file, md5);
            String status = resumeInfo.getString("status");
            
            if ("resume".equals(status)) {
                taskId = resumeInfo.getString("taskId");
                offset = resumeInfo.getLongValue("uploadedSize");
                System.out.println("发现断点记录，taskId: " + taskId + ", 已上传: " + formatBytes(offset) + ", 继续上传...");
            } else if ("new".equals(status)) {
                System.out.println("无断点记录，开始全新上传...");
                // 3. 发送元数据帧
                taskId = sendMeta(channel, file, md5);
                System.out.println("元数据握手成功，获取新taskId: " + taskId);
            } else {
                throw new RuntimeException("服务端拒绝上传: " + resumeInfo.getString("message"));
            }

            // 4. 发送文件数据
            if (offset < file.length()) {
                sendData(channel, file, offset, taskId);
            } else {
                System.out.println("文件已完整上传，无需发送数据.");
            }

            // 5. 发送结束帧
            sendEnd(channel, taskId);
            
            System.out.println("✅ 文件上传流程结束.");

        } catch (IOException e) {
            System.err.println("网络连接异常: " + e.getMessage());
            throw e;
        }
    }

    // Check Resume: Send RESUME_CHECK -> Recv RESUME_ACK
    private static JSONObject checkResume(SocketChannel channel, File file, String md5) throws IOException {
        JSONObject checkReq = new JSONObject();
        checkReq.put("md5", md5);
        checkReq.put("fileName", file.getName());
        checkReq.put("fileSize", file.length());
        checkReq.put("fileType", getExtension(file.getName()));
        checkReq.put("dirId", 7416750131732578304L); // 可根据所选择的目录Id进行设置, 本次为测试用
        checkReq.put("userId", 1001L); // 测试用户ID
        
        sendFrame(channel, RESUME_CHECK, checkReq.toJSONString().getBytes(StandardCharsets.UTF_8));
        
        Frame response = readFrame(channel);
        if (response.type != RESUME_ACK) {
            throw new IOException("断点检查响应类型错误: " + response.type);
        }
        
        return JSON.parseObject(new String(response.data, StandardCharsets.UTF_8));
    }

    // Send Meta: Send META_FRAME -> Recv ACK_FRAME (ready)
    private static String sendMeta(SocketChannel channel, File file, String md5) throws IOException {
        JSONObject meta = new JSONObject();
        meta.put("md5", md5);
        meta.put("fileName", file.getName());
        meta.put("fileSize", file.length());
        meta.put("fileType", getExtension(file.getName()));
        meta.put("dirId", 7416750131732578304L); // 可根据所选择的目录Id进行设置, 本次为测试用
        meta.put("userId", 1001L);

        sendFrame(channel, META_FRAME, meta.toJSONString().getBytes(StandardCharsets.UTF_8));

        Frame response = readFrame(channel);
        if (response.type != ACK_FRAME) {
            throw new IOException("元数据响应类型错误: " + response.type);
        }
        
        JSONObject ack = JSON.parseObject(new String(response.data, StandardCharsets.UTF_8));
        if (!"ready".equals(ack.getString("status"))) {
            throw new IOException("服务端未就绪: " + ack.getString("message"));
        }
        
        return ack.getString("taskId");
    }

    // Send Data: Loop chunks -> DATA_FRAME
    private static void sendData(SocketChannel channel, File file, long offset, String taskId) throws IOException {
        try (RandomAccessFile raf = new RandomAccessFile(file, "r")) {
            raf.seek(offset);
            byte[] fileBuffer = new byte[CHUNK_SIZE];
            int readLen;
            long totalSent = offset;
            long fileSize = file.length();
            
            long startTime = System.currentTimeMillis();
            long lastLogTime = startTime;
            
            while ((readLen = raf.read(fileBuffer)) != -1) {
                // 如果是最后一块，只发送实际长度
                byte[] dataToSend = fileBuffer;
                if (readLen < CHUNK_SIZE) {
                    dataToSend = new byte[readLen];
                    System.arraycopy(fileBuffer, 0, dataToSend, 0, readLen);
                }
                
                sendFrame(channel, DATA_FRAME, dataToSend);
                totalSent += readLen;
                
                // 打印进度 (每500ms)
                long now = System.currentTimeMillis();
                if (now - lastLogTime > 500 || totalSent == fileSize) {
                    double progress = totalSent * 100.0 / fileSize;
                    double speed = (totalSent - offset) / 1024.0 / 1024.0 / ((now - startTime) / 1000.0 + 0.1); // MB/s
                    System.out.printf("\r正在上传: %.2f%% (%s/%s) 速率: %.2f MB/s", 
                            progress, formatBytes(totalSent), formatBytes(fileSize), speed);
                    lastLogTime = now;
                }
            }
            System.out.println(); // 换行
        }
    }

    // Send End: Send END_FRAME -> Recv ACK_FRAME (success)
    private static void sendEnd(SocketChannel channel, String taskId) throws IOException {
        JSONObject endParams = new JSONObject();
        endParams.put("taskId", taskId);
        
        sendFrame(channel, END_FRAME, endParams.toJSONString().getBytes(StandardCharsets.UTF_8));
        
        Frame response = readFrame(channel);
        if (response.type != ACK_FRAME) {
            throw new IOException("结束帧响应类型错误: " + response.type);
        }
        
        JSONObject ack = JSON.parseObject(new String(response.data, StandardCharsets.UTF_8));
        if ("success".equals(ack.getString("status"))) {
            System.out.println("服务端确认上传成功!");
        } else {
            System.err.println("服务端报错: " + ack.getString("message"));
        }
    }

    // Protocol: Helper to write a frame
    private static void sendFrame(SocketChannel channel, byte type, byte[] data) throws IOException {
        int len = (data == null) ? 0 : data.length;
        ByteBuffer buffer = ByteBuffer.allocate(HEADER_LENGTH + len);
        
        buffer.put(MAGIC);
        buffer.put(type);
        buffer.put((byte) 0); // Flags
        buffer.putInt(len);
        if (data != null) {
            buffer.put(data);
        }
        
        buffer.flip();
        while (buffer.hasRemaining()) {
            channel.write(buffer);
        }
    }

    // Protocol: Helper to read a frame
    private static Frame readFrame(SocketChannel channel) throws IOException {
        ByteBuffer header = ByteBuffer.allocate(HEADER_LENGTH);
        while (header.hasRemaining()) {
            if (channel.read(header) == -1) throw new IOException("连接已关闭");
        }
        header.flip();
        
        byte[] magic = new byte[2];
        header.get(magic);
        if (magic[0] != MAGIC[0] || magic[1] != MAGIC[1]) {
            throw new IOException("无效的魔数: " + String.format("%02X %02X", magic[0], magic[1]));
        }
        
        byte type = header.get();
        byte flags = header.get();
        int len = header.getInt();
        
        byte[] data = new byte[len];
        if (len > 0) {
            ByteBuffer body = ByteBuffer.allocate(len);
            while (body.hasRemaining()) {
                if (channel.read(body) == -1) throw new IOException("读取数据体时连接关闭");
            }
            body.flip();
            body.get(data);
        }
        
        return new Frame(type, data);
    }

    static class Frame {
        byte type;
        byte[] data;
        
        Frame(byte type, byte[] data) {
            this.type = type;
            this.data = data;
        }
    }
    
    // MD5 Calculator
    private static String calculateMD5(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("MD5");
        try (FileInputStream fis = new FileInputStream(file)) {
            byte[] buffer = new byte[8192];
            int n;
            while ((n = fis.read(buffer)) != -1) {
                digest.update(buffer, 0, n);
            }
        }
        byte[] hash = digest.digest();
        StringBuilder sb = new StringBuilder();
        for (byte b : hash) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
    
    private static String getExtension(String fileName) {
        int idx = fileName.lastIndexOf(".");
        return (idx == -1) ? "" : fileName.substring(idx + 1);
    }
    
    private static String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return String.format("%.2f KB", bytes / 1024.0);
        return String.format("%.2f MB", bytes / 1024.0 / 1024.0);
    }
}
