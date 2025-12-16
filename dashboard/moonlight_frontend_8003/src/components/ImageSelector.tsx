/**
 * ImageSelector Component
 * Moonlight 이미지 선택 카드
 */

import {
  Card,
  CardContent,
  CardActions,
  Typography,
  Button,
  Box,
  Chip,
} from '@mui/material';
import { CheckCircle, Cancel, Computer } from '@mui/icons-material';
import type { MoonlightImage } from '../api/moonlight';

interface ImageSelectorProps {
  images: MoonlightImage[];
  selectedImage: string | null;
  onSelect: (imageId: string) => void;
  onCreateSession: (imageId: string) => void;
  loading?: boolean;
}

export const ImageSelector = ({
  images,
  selectedImage,
  onSelect,
  onCreateSession,
  loading = false,
}: ImageSelectorProps) => {
  return (
    <Box
      sx={{
        display: 'grid',
        gridTemplateColumns: {
          xs: '1fr',
          sm: 'repeat(2, 1fr)',
          md: 'repeat(3, 1fr)',
        },
        gap: 3,
      }}
    >
      {images.map((image) => (
        <Box key={image.id}>
          <Card
            sx={{
              height: '100%',
              display: 'flex',
              flexDirection: 'column',
              border: selectedImage === image.id ? '2px solid #1976d2' : '1px solid #e0e0e0',
              cursor: 'pointer',
              transition: 'all 0.3s',
              '&:hover': {
                boxShadow: 6,
                transform: 'translateY(-4px)',
              },
            }}
            onClick={() => onSelect(image.id)}
          >
            <CardContent sx={{ flexGrow: 1 }}>
              <Box display="flex" alignItems="center" mb={2}>
                <Typography variant="h4" component="span" mr={1}>
                  {image.icon}
                </Typography>
                <Typography variant="h6" component="div">
                  {image.name}
                </Typography>
              </Box>

              <Typography variant="body2" color="text.secondary" mb={2}>
                {image.description}
              </Typography>

              <Box display="flex" gap={1} flexWrap="wrap">
                {image.default && (
                  <Chip
                    label="Default"
                    size="small"
                    color="primary"
                    variant="outlined"
                  />
                )}
                {image.available ? (
                  <Chip
                    icon={<CheckCircle />}
                    label="Available"
                    size="small"
                    color="success"
                  />
                ) : (
                  <Chip
                    icon={<Cancel />}
                    label="Not Built"
                    size="small"
                    color="error"
                  />
                )}
              </Box>
            </CardContent>

            <CardActions>
              <Button
                fullWidth
                variant={selectedImage === image.id ? 'contained' : 'outlined'}
                onClick={(e) => {
                  e.stopPropagation();
                  onCreateSession(image.id);
                }}
                disabled={!image.available || loading}
                startIcon={<Computer />}
              >
                {loading ? 'Creating...' : 'Start Session'}
              </Button>
            </CardActions>
          </Card>
        </Box>
      ))}
    </Box>
  );
};
