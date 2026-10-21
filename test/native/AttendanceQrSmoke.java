import com.google.zxing.*;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.common.HybridBinarizer;
import java.util.*;

/** JVM check of the same ZXing luminance/reader pipeline used after PixelCopy.
 * Synthetic frames only: this is not proof of a real Android/video capture. */
public class AttendanceQrSmoke {
  static String decode(int[] pixels, int size) throws Exception {
    var source = new RGBLuminanceSource(size,size,pixels);
    var reader = new MultiFormatReader();
    try {
      return reader.decode(new BinaryBitmap(new HybridBinarizer(source)),
        Map.of(DecodeHintType.POSSIBLE_FORMATS,List.of(BarcodeFormat.QR_CODE))).getText();
    } finally { reader.reset(); }
  }
  public static void main(String[] args) throws Exception {
    int passed=0, size=480;
    for(String token:List.of("old-frame","latest-frame")) {
      String value="https://mlearning.sjtu.edu.cn/lms/mobile2/forscan/?courseCode=fixture&rollCallToken="+token+"&signHistoryId=fixture-task&fromType=scanRollCall";
      BitMatrix matrix = new MultiFormatWriter().encode(value,BarcodeFormat.QR_CODE,size,size);
      int[] pixels=new int[size*size];
      for(int y=0;y<size;y++) for(int x=0;x<size;x++) pixels[y*size+x]=matrix.get(x,y)?0xff000000:0xffffffff;
      if(!decode(pixels,size).equals(value)) throw new AssertionError("decode mismatch");
      passed++;
      int[] rotated=new int[pixels.length];
      for(int y=0;y<size;y++) for(int x=0;x<size;x++) rotated[x*size+size-1-y]=pixels[y*size+x];
      if(!decode(rotated,size).equals(value)) throw new AssertionError("rotation mismatch");
      passed++;
    }
    for(int color:new int[]{0xff000000,0xffffffff}) {
      int[] pixels=new int[size*size];Arrays.fill(pixels,color);
      try { decode(pixels,size); throw new AssertionError("flat frame decoded"); }
      catch(NotFoundException expected){passed++;}
    }
    System.out.println(passed+" synthetic ZXing frame checks passed.");
  }
}
